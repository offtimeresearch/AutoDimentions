#!/usr/bin/env python3
from pathlib import Path
import sys

src = Path(sys.argv[1] if len(sys.argv) > 1 else "TopologyExtractor.vb")
raw = src.read_bytes()
changed = False

# iLogic header directives such as AddReference must be the first real token.
# A UTF-8 BOM can prevent iLogic from recognizing AddReference as a header directive.
if raw.startswith(b"\xef\xbb\xbf"):
    raw = raw[3:]
    changed = True

text = raw.decode("utf-8")

# Normalize the first AddReference spelling. Autodesk says the .dll suffix is optional,
# but using it makes the intent explicit.
old = 'AddReference "System.Windows.Forms"'
new = 'AddReference "System.Windows.Forms.dll"'
if text.startswith(old):
    text = new + text[len(old):]
    changed = True

# Keep Windows-friendly CRLF line endings for copy/paste into Inventor's rule editor.
normalized = text.replace("\r\n", "\n").replace("\r", "\n").replace("\n", "\r\n")
if normalized != text:
    changed = True

src.write_bytes(normalized.encode("utf-8"))
print(f"normalized={changed} bytes={src.stat().st_size}")
