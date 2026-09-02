#!/usr/bin/env python3
from pathlib import Path

src = Path('TopologyExtractor.vb')
text = src.read_text(encoding='utf-8-sig')

old_pipe = 'If d.ConnectionType = "PIPE_LENGTH" Then'
new_pipe = 'If d.DimensionType = "PIPE_LENGTH" Then'
old_flange = 'ElseIf d.ConnectionType = "FLANGE_THICKNESS" Then'
new_flange = 'ElseIf d.DimensionType = "FLANGE_THICKNESS" Then'

if old_pipe not in text:
    raise SystemExit('Expected PIPE_LENGTH ConnectionType reference not found')
if old_flange not in text:
    raise SystemExit('Expected FLANGE_THICKNESS ConnectionType reference not found')

text = text.replace(old_pipe, new_pipe, 1)
text = text.replace(old_flange, new_flange, 1)

# Keep plain UTF-8 with CRLF and no BOM for Inventor copy/paste.
text = text.replace('\r\n', '\n').replace('\r', '\n').replace('\n', '\r\n')
src.write_bytes(text.encode('utf-8'))

print('Fixed V0.9 attachment renderer: DimensionRecord.ConnectionType -> DimensionType')
