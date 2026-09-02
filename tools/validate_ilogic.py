#!/usr/bin/env python3
import re, sys
from pathlib import Path

SRC = Path(sys.argv[1] if len(sys.argv) > 1 else 'Topology Extractor.iLogicVb')
text = SRC.read_text(encoding='utf-8-sig')
lines = text.splitlines()
errors=[]; warnings=[]

def err(line,msg): errors.append((line,msg))
def warn(line,msg): warnings.append((line,msg))

if 'AUTOSPOOL - SINGLE SPOOL TOPOLOGY / DIMENSION VERIFIER V0.4' not in text:
    warn(1,'Expected V0.4 source marker not found')

# Known iLogic troublemakers from previous iterations
for i,l in enumerate(lines,1):
    if re.match(r'\s*Imports\s+System\.IO\b',l,re.I):
        err(i,'Do not import System.IO in iLogic: Inventor.Path/File become ambiguous. Use System.IO.Path/File explicitly.')
    # unqualified Path./File. outside strings/comments
    code=l.split("'",1)[0]
    code=re.sub(r'"(?:[^"]|"")*"','',code)
    if re.search(r'(?<!System\.IO\.)\b(?:Path|File)\s*\.',code):
        err(i,'Unqualified Path./File. reference may be ambiguous with Inventor.')
    if re.match(r'\s*Return\s*$',code,re.I):
        # determine if inside function below
        pass
    if re.search(r'_\s+[^\']', code) and not code.rstrip().endswith('_'):
        warn(i,'Possible malformed VB line continuation underscore.')

# Procedure/class balance and duplicate names
starts={'sub':0,'function':0,'class':0}
ends={'sub':0,'function':0,'class':0}
name_seen={}
stack=[]
current_proc=[]
for i,l in enumerate(lines,1):
    code=l.split("'",1)[0].strip()
    m=re.match(r'(?:(?:Public|Private|Friend|Protected|Shared|Static|Overloads|Overrides|MustOverride|NotOverridable|Overridable|Partial)\s+)*(Sub|Function|Class)\s+([A-Za-z_]\w*)\b',code,re.I)
    if m:
        kind=m.group(1).lower(); name=m.group(2)
        starts[kind]+=1
        key=(kind,name.lower())
        if name.lower() != 'new':
            if key in name_seen: err(i,f'Duplicate {kind} {name}; first declared line {name_seen[key]}.')
            else: name_seen[key]=i
        else:
            name_seen[(kind, name.lower() + '@' + str(i))]=i
        stack.append((kind,name,i))
        if kind in ('sub','function'): current_proc.append((kind,name,i))
        continue
    m=re.match(r'End\s+(Sub|Function|Class)\b',code,re.I)
    if m:
        kind=m.group(1).lower(); ends[kind]+=1
        # loose matching sufficient for iLogic source validation
        if not stack:
            err(i,f'End {kind} without opener.')
        else:
            ok=None
            for idx in range(len(stack)-1,-1,-1):
                if stack[idx][0]==kind:
                    ok=idx; break
            if ok is None: err(i,f'End {kind} without matching opener.')
            else:
                stack.pop(ok)
        if kind in ('sub','function') and current_proc:
            for idx in range(len(current_proc)-1,-1,-1):
                if current_proc[idx][0]==kind:
                    current_proc.pop(idx); break
        continue
    if re.match(r'Return\s*$',code,re.I):
        if current_proc and current_proc[-1][0]=='function':
            err(i,f'Bare Return inside Function {current_proc[-1][1]}; a value is required.')

for kind in starts:
    if starts[kind] != ends[kind]:
        err(0,f'{kind.title()} count mismatch: {starts[kind]} starts vs {ends[kind]} ends.')

# Namespace-level Dim/Const: iLogic rejects these. Track whether inside Sub/Function/Class.
depth_proc=0; depth_class=0
for i,l in enumerate(lines,1):
    code=l.split("'",1)[0].strip()
    if re.match(r'(?:(?:Public|Private|Friend|Protected|Shared|Static|Overloads|Overrides|MustOverride|NotOverridable|Overridable|Partial)\s+)*(Sub|Function)\b',code,re.I): depth_proc+=1
    elif re.match(r'End\s+(Sub|Function)\b',code,re.I): depth_proc=max(0,depth_proc-1)
    elif re.match(r'(?:(?:Public|Private|Friend|Protected|Partial)\s+)*Class\b',code,re.I): depth_class+=1
    elif re.match(r'End\s+Class\b',code,re.I): depth_class=max(0,depth_class-1)
    elif depth_proc==0 and depth_class==0 and re.match(r'(Dim|Const)\b',code,re.I):
        err(i,'Namespace-level Dim/Const is invalid in iLogic. Put settings inside a Sub/Function or a Class.')

# Parentheses balance per logical statement, ignoring strings/comments.
buf=''; start_line=1
for i,l in enumerate(lines,1):
    code=l.split("'",1)[0]
    # remove VB strings including doubled quotes
    code=re.sub(r'"(?:[^"]|"")*"','',code)
    if not buf: start_line=i
    cont=code.rstrip().endswith('_')
    if cont: code=code.rstrip()[:-1]
    buf += ' ' + code
    if cont: continue
    bal=0
    bad=False
    for ch in buf:
        if ch=='(': bal+=1
        elif ch==')':
            bal-=1
            if bal<0: bad=True; break
    if bad or bal!=0:
        err(start_line,f'Parentheses appear unbalanced in logical statement (balance={bal}).')
    buf=''
if buf.strip(): err(start_line,'File ends during a continued logical statement.')

# Case-insensitive local variable names that shadow helper Function names.
functions={name.lower():line for (kind,name),line in name_seen.items() if kind=='function'}
for i,l in enumerate(lines,1):
    code=l.split("'",1)[0]
    m=re.search(r'\bDim\s+([A-Za-z_]\w*)\s+As\b',code,re.I)
    if m and m.group(1).lower() in functions:
        err(i,f'Local variable {m.group(1)} shadows Function {m.group(1)} (VB is case-insensitive).')

print(f'Validating: {SRC}')
print(f'Lines: {len(lines)}')
for line,msg in warnings: print(f'WARNING L{line}: {msg}')
for line,msg in errors: print(f'ERROR L{line}: {msg}')
if errors:
    print(f'FAILED: {len(errors)} error(s), {len(warnings)} warning(s)')
    sys.exit(1)
print(f'PASS: static iLogic/VB checks completed ({len(warnings)} warning(s)).')
print('NOTE: Inventor API/runtime behavior cannot be executed on GitHub-hosted runners; final runtime test still happens inside Autodesk Inventor.')
