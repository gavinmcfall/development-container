import json,os,re,glob,sys
from collections import defaultdict

DIR=os.path.expanduser("~/.claude/projects")
SEG=re.compile(r'\|\||&&|[|;&]|\$\(|\)|`|\n')      # split a compound command into segments
ENVPREFIX=re.compile(r'^[A-Z_][A-Z0-9_]*=\S*$')    # VAR=val prefix to skip
SKIP={'sudo','env','command','time','nohup','exec','then','do','done','fi','else','elif','if','for','while','{','}','(',')','&&','||'}
count=defaultdict(int); last=defaultdict(str)

def heads(cmd):
    for seg in SEG.split(cmd):
        toks=seg.strip().split()
        i=0
        while i<len(toks) and (ENVPREFIX.match(toks[i]) or toks[i] in SKIP):
            i+=1
        if i<len(toks):
            t=toks[i].split('/')[-1].strip('"\'')
            if re.fullmatch(r'[A-Za-z][A-Za-z0-9._-]{0,30}', t):
                yield t

nfiles=0
for f in glob.glob(os.path.join(DIR,'**','*.jsonl'),recursive=True):
    nfiles+=1
    try:
        for line in open(f,errors='ignore'):
            if '"tool_use"' not in line or '"Bash"' not in line: continue
            try: o=json.loads(line)
            except: continue
            ts=o.get("timestamp","")
            msg=o.get("message",{}); content=msg.get("content") if isinstance(msg,dict) else None
            if not isinstance(content,list): continue
            for c in content:
                if isinstance(c,dict) and c.get("type")=="tool_use" and c.get("name")=="Bash":
                    cmd=c.get("input",{}).get("command","")
                    for h in set(heads(cmd)):
                        count[h]+=1
                        if ts>last[h]: last[h]=ts
    except Exception: continue

print(f"parsed {nfiles} transcripts; {len(count)} distinct tool-heads invoked by Claude\n")
print("=== TOP 35 tools Claude invokes (count | last-used) ===")
for t,n in sorted(count.items(),key=lambda x:-x[1])[:35]:
    print(f"  {t:<16} {n:>6}  {last[t][:10]}")

# cross-ref the 'drop candidates' Gavin never types — does Claude use them?
print("\n=== do CLAUDE-side invocations rescue the 'never typed' tools? ===")
for t in ['cilium-cli','cilium','go-task','task','age','helmfile','dive','git-crypt','shellcheck','stern','krew','kubeconform','tesseract','sops','talosctl','skopeo','rclone','restic','ffmpeg','jq','rg','fd']:
    print(f"  {t:<14} count={count.get(t,0):<5} last={last.get(t,'NEVER')[:10]}")
# save full table
with open('/tmp/claude_tool_usage.csv','w') as out:
    out.write("tool,count,last_used\n")
    for t,n in sorted(count.items(),key=lambda x:-x[1]):
        out.write(f"{t},{n},{last[t]}\n")
print("\nfull table -> /tmp/claude_tool_usage.csv")
