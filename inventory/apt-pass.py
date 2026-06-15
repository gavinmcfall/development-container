import csv,os,subprocess,re
from collections import defaultdict
HOME=os.path.expanduser("~")
DB=f"{HOME}/.local/share/atuin/history.db"

# ---- merged usage map: binary-head -> (count, last_date) ----
cnt=defaultdict(int); last=defaultdict(str)
import datetime
for line in subprocess.run(["sqlite3","-separator","\t",DB,"SELECT command,timestamp FROM history"],
                           capture_output=True,text=True).stdout.splitlines():
    if "\t" not in line: continue
    cmd,ts=line.rsplit("\t",1); h=cmd.strip().split()[0].split("/")[-1] if cmd.strip() else ""
    if not h: continue
    cnt[h]+=1
    try: d=datetime.datetime.fromtimestamp(int(ts)/1e9,datetime.UTC).strftime("%Y-%m-%d")
    except: d=""
    if d>last[h]: last[h]=d
for r in csv.DictReader(open(f"{HOME}/scratch/devpod-migration/inventory/claude-tool-usage.csv")):
    cnt[r["tool"]]+=int(r["count"])
    if r["last_used"][:10]>last[r["tool"]]: last[r["tool"]]=r["last_used"][:10]

# ---- package metadata ----
meta={}
for line in subprocess.run(["dpkg-query","-W","-f=${Package}\t${Priority}\t${Essential}\n"],
                           capture_output=True,text=True).stdout.splitlines():
    p=line.split("\t"); meta[p[0]]={"prio":p[1] if len(p)>1 else "","ess":p[2] if len(p)>2 else "no"}

pkgs=[l.strip() for l in open(f"{HOME}/scratch/devpod-migration/inventory/apt-manual.txt") if l.strip()]
BINRE=re.compile(r'^(/usr)?/s?bin/([^/]+)$')
keep=[];drop=[];nobin=[];base=[]
for pkg in pkgs:
    m=meta.get(pkg,{"prio":"","ess":"no"})
    if m["ess"]=="yes" or m["prio"] in ("required","important"):
        base.append(pkg); continue
    bins=[]
    for f in subprocess.run(["dpkg","-L",pkg],capture_output=True,text=True).stdout.splitlines():
        mm=BINRE.match(f)
        if mm: bins.append(mm.group(2))
    if not bins:
        nobin.append(pkg); continue
    used=[(b,cnt[b],last[b]) for b in bins if cnt.get(b,0)>0]
    if used:
        tot=sum(u[1] for u in used); lu=max(u[2] for u in used)
        keep.append((pkg,tot,lu))
    else:
        drop.append((pkg,bins))

keep.sort(key=lambda x:-x[1])
print(f"apt manual: {len(pkgs)} | base/essential: {len(base)} | lib/no-bin: {len(nobin)} | KEEP: {len(keep)} | DROP-candidate: {len(drop)}\n")
print("=== KEEP (binary used; top 40) ===")
for p,n,l in keep[:40]: print(f"  {p:<28} {n:>5}  {l}")
print(f"\n=== DROP candidates ({len(drop)}) — apt apps whose binaries are NEVER invoked ===")
for p,bins in sorted(drop):
    print(f"  {p:<26} bins: {','.join(bins[:4])}")
# persist
with open("/tmp/apt_keep.csv","w") as o:
    o.write("package,count,last\n")
    for p,n,l in keep: o.write(f"{p},{n},{l}\n")
with open("/tmp/apt_drop.txt","w") as o:
    o.write("\n".join(p for p,_ in sorted(drop)))
print(f"\nlib/no-bin (keep by dependency, {len(nobin)}): not invocable; e.g.",", ".join(nobin[:12]))
