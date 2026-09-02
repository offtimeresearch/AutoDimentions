#!/usr/bin/env python3
import re
import sys
from pathlib import Path

SRC = Path(sys.argv[1] if len(sys.argv) > 1 else "Topology Extractor.iLogicVb")
raw = SRC.read_bytes()
errors = []
warnings = []

def err(line, msg):
    errors.append((line, msg))

def warn(line, msg):
    warnings.append((line, msg))

# Critical iLogic header check: do NOT silently consume a BOM.
if raw.startswith(b"\xef\xbb\xbf"):
    err(1, "UTF-8 BOM found before AddReference. iLogic may parse AddReference as normal VB and cascade into Imports/type errors.")

try:
    text = raw.decode("utf-8")
except UnicodeDecodeError as ex:
    print(f"ERROR: source is not UTF-8: {ex}")
    sys.exit(1)

lines = text.replace("\r\n", "\n").replace("\r", "\n").split("\n")

# Header structure expected by iLogic.
first_nonblank = next(((i, l.strip()) for i, l in enumerate(lines, 1) if l.strip()), (0, ""))
if first_nonblank[1] not in ('AddReference "System.Windows.Forms"', 'AddReference "System.Windows.Forms.dll"'):
    err(first_nonblank[0] or 1, "First nonblank line should be AddReference for System.Windows.Forms.")

main_line = None
for i, line in enumerate(lines, 1):
    if re.match(r"^\s*Sub\s+Main\s*\(\s*\)\s*$", line, re.I):
        main_line = i
        break

if main_line is None:
    err(1, "Sub Main() not found.")
else:
    # Before Sub Main, only iLogic/VB header directives, blank lines and comments are allowed.
    allowed = re.compile(r"^\s*(?:$|'|Imports\b|AddReference\b|Option\b|AddVbRule\b|AddVbFile\b|AddResources\b)", re.I)
    for i, line in enumerate(lines[: main_line - 1], 1):
        if not allowed.match(line):
            err(i, "Unexpected declaration/statement before Sub Main(); this can make later Imports invalid in iLogic.")

# Imports must be in the header, not after declarations begin.
if main_line is not None:
    for i, line in enumerate(lines[main_line:], main_line + 1):
        if re.match(r"^\s*Imports\b", line, re.I):
            err(i, "Imports found after Sub Main()/declarations. Keep all Imports in the iLogic header.")

if "AUTOSPOOL - SINGLE SPOOL TOPOLOGY / DIMENSION VERIFIER V0.4" not in text:
    warn(1, "Expected V0.4 source marker not found.")

# Known iLogic troublemakers from earlier iterations.
for i, line in enumerate(lines, 1):
    if re.match(r"\s*Imports\s+System\.IO\b", line, re.I):
        err(i, "Do not import System.IO in this rule; use System.IO.Path/File explicitly to avoid Inventor name ambiguity.")

# Crude block-balance checks. These are not a full VB compiler, but catch truncation/editing mistakes.
patterns = [
    (r"^\s*Sub\s+(?!Main\b)", r"^\s*End\s+Sub\s*$", "Sub"),
    (r"^\s*Function\s+", r"^\s*End\s+Function\s*$", "Function"),
    (r"^\s*Class\s+", r"^\s*End\s+Class\s*$", "Class"),
]
for start_pat, end_pat, name in patterns:
    starts = sum(1 for l in lines if re.match(start_pat, l, re.I))
    ends = sum(1 for l in lines if re.match(end_pat, l, re.I))
    if name == "Sub":
        # Include Main in total End Sub count comparison.
        starts += 1 if main_line is not None else 0
    if starts != ends:
        err(1, f"Unbalanced {name} blocks: starts={starts}, ends={ends}.")

# Parenthesis sanity after stripping comments and quoted strings approximately.
def strip_strings_and_comments(line):
    out = []
    i = 0
    in_string = False
    while i < len(line):
        ch = line[i]
        if in_string:
            if ch == '"':
                if i + 1 < len(line) and line[i + 1] == '"':
                    i += 2
                    continue
                in_string = False
            i += 1
            continue
        if ch == '"':
            in_string = True
            i += 1
            continue
        if ch == "'":
            break
        out.append(ch)
        i += 1
    return "".join(out)

balance = 0
for i, line in enumerate(lines, 1):
    cleaned = strip_strings_and_comments(line)
    balance += cleaned.count("(") - cleaned.count(")")
    if balance < 0:
        err(i, "Closing parenthesis appears before a matching opening parenthesis.")
        balance = 0
if balance != 0:
    err(len(lines), f"Parenthesis balance at EOF is {balance}; source may be truncated or malformed.")

for line_no, msg in warnings:
    print(f"WARNING line {line_no}: {msg}")
for line_no, msg in errors:
    print(f"ERROR line {line_no}: {msg}")

if errors:
    print(f"FAILED: {len(errors)} error(s), {len(warnings)} warning(s)")
    sys.exit(1)

print(f"PASS: {SRC} | lines={len(lines)} | bytes={len(raw)} | warnings={len(warnings)}")
