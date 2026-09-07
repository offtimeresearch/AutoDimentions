#!/usr/bin/env python3
"""Build the self-contained AutoCAD GTP district-heating toolkit.

The repository evolved as a stable geometry engine plus component integration
steps. This builder preserves that architecture while producing one APPLOAD-able
LSP file. Later integration modules intentionally override earlier function
names, matching the required runtime load order.
"""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "GTP_DH_TOOLKIT_COMBINED.lsp"
CORE = ROOT / "GTP_DH_TOOLKIT.lsp"
BRIDGE = ROOT / "GTP_Combined_Final_Bridge.lsp"
SMART = ROOT / "GTP_Smart_Pipe_Command.lsp"

MODULES = [
    ROOT / "GTP_Component_Architecture.lsp",
    ROOT / "GTP_Elbow_Component_Integration.lsp",
    ROOT / "GTP_Valve_Component.lsp",
    ROOT / "GTP_Valve_Aware_Pipe_Integration.lsp",
    ROOT / "GTP_Valve_Catalogue_Integration.lsp",
    ROOT / "GTP_Component_Persistence_and_Fittings.lsp",
]

MASTER_COMPONENT_MARKER = (
    "; =============================================================================\n"
    "; MASTER COMPONENT INTEGRATION\n"
    "; ============================================================================="
)

FIXUPS = {
    "(gtp:component-get component 'id')": "(gtp:component-get component 'id)",
    "(gtp:casing-od dn series)": "(gtp:casing-od row series)",
}

REQUIRED_COMMANDS = [
    "GTPPIPE",
    "GTPPIPESMART",
    "GTPMITER",
    "GTPMITTER",
    "GTPUNITS",
    "GTPLAYER",
    "GTPVALVE",
    "GTPVALVECATALOG",
    "GTPVALVESUMMARY",
    "GTPTEE",
    "GTPREDUCER",
    "GTPBRANCH",
    "GTPENDCAP",
    "GTPCOMPONENTS",
    "GTPCOMPONENTRELOAD",
    "GTPCOMPONENTSAVE",
    "GTPCOMBINEDTEST",
    "GTPSMARTTEST",
    "GTPHELP",
]


def read(path: Path) -> str:
    if not path.exists():
        raise SystemExit(f"Missing required source: {path.relative_to(ROOT)}")
    return path.read_text(encoding="utf-8").replace("\r\n", "\n")


def sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def strip_legacy_master_component_block(core: str) -> str:
    idx = core.find(MASTER_COMPONENT_MARKER)
    if idx < 0:
        raise SystemExit(
            "Could not find MASTER COMPONENT INTEGRATION marker in GTP_DH_TOOLKIT.lsp"
        )
    return core[:idx].rstrip() + "\n"


def banner(title: str) -> str:
    line = "; " + "=" * 75
    return f"\n{line}\n; BEGIN COMBINED SOURCE: {title}\n{line}\n"


def build_text() -> str:
    core_full = read(CORE)
    core_geometry = strip_legacy_master_component_block(core_full)

    sources: list[tuple[str, str]] = [
        (CORE.name + " [geometry core only]", core_geometry)
    ]
    for module in MODULES:
        sources.append((module.name, read(module)))
    sources.append((BRIDGE.name, read(BRIDGE)))
    sources.append((SMART.name, read(SMART)))

    manifest = [
        "; GTP_DH_TOOLKIT_COMBINED.LSP",
        "; =============================================================================",
        "; SELF-CONTAINED GENERATED BUILD - APPLOAD ONLY THIS FILE",
        ";",
        "; Generated from the proven GTP geometry core, component Steps 1-6,",
        "; the final multi-component route bridge, and the intelligent GTPPIPE",
        "; single-session workflow. Do not hand-edit this generated file;",
        "; edit the source modules and run tools/build_gtp_combined.py instead.",
        ";",
        "; Source manifest (SHA-256 of included text):",
    ]
    for name, text in sources:
        manifest.append(f";   {name}: {sha256_text(text)}")
    manifest.extend(
        [
            ";",
            "; Architecture:",
            ";   route -> one-time setup -> component placement menu -> route cleanup",
            ";   -> elbow footprints -> persistent component footprints",
            ";   -> remaining straight intervals -> stock-length spools -> 3D solids",
            "; =============================================================================",
            "",
        ]
    )

    out = "\n".join(manifest)
    for name, text in sources:
        out += banner(name)
        out += text.rstrip() + "\n"

    for old, new in FIXUPS.items():
        out = out.replace(old, new)

    return out


def validate_lisp(text: str) -> None:
    depth = 0
    in_string = False
    escaped = False
    line = 1
    min_depth = 0

    i = 0
    while i < len(text):
        ch = text[i]
        if ch == "\n":
            line += 1
            i += 1
            continue

        if in_string:
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == '"':
                in_string = False
            i += 1
            continue

        if ch == '"':
            in_string = True
            i += 1
            continue

        if ch == ";":
            nl = text.find("\n", i)
            if nl < 0:
                break
            i = nl
            continue

        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
            min_depth = min(min_depth, depth)
            if depth < 0:
                raise SystemExit(f"AutoLISP parenthesis underflow near line {line}")
        i += 1

    if in_string:
        raise SystemExit("Unterminated AutoLISP string literal")
    if depth != 0:
        raise SystemExit(f"Unbalanced AutoLISP parentheses: final depth={depth}")
    if min_depth < 0:
        raise SystemExit("AutoLISP parenthesis validation failed")

    for command in REQUIRED_COMMANDS:
        needle = f"(defun c:{command}"
        if needle not in text:
            raise SystemExit(f"Missing required combined command: {command}")

    if MASTER_COMPONENT_MARKER in text:
        raise SystemExit("Legacy master component block leaked into combined build")

    if "GTP integrated load:" in text or "*gtp-integrated-module-list*" in text:
        raise SystemExit("Combined build must not depend on the multi-file loader")

    if "Final multi-component route modeller active." not in text:
        raise SystemExit("Final combined route bridge is missing")

    if "GTPPIPE now runs one-route/one-setup component-aware modelling." not in text:
        raise SystemExit("Intelligent GTPPIPE override is missing")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--check",
        action="store_true",
        help="Validate sources and fail if GTP_DH_TOOLKIT_COMBINED.lsp is stale.",
    )
    args = parser.parse_args()

    text = build_text()
    validate_lisp(text)

    if args.check:
        if not OUTPUT.exists():
            print(f"Missing generated output: {OUTPUT.name}", file=sys.stderr)
            return 1
        current = read(OUTPUT)
        if current != text:
            print(
                f"{OUTPUT.name} is stale; run tools/build_gtp_combined.py",
                file=sys.stderr,
            )
            return 1
        print(
            f"{OUTPUT.name} is current | {len(text.splitlines())} lines | "
            f"sha256={sha256_text(text)}"
        )
        return 0

    OUTPUT.write_text(text, encoding="utf-8", newline="\n")
    print(
        f"Wrote {OUTPUT.name} | {len(text.splitlines())} lines | "
        f"sha256={sha256_text(text)}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
