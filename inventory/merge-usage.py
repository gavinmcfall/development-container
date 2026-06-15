import csv,os,subprocess
from collections import defaultdict
HOME=os.path.expanduser("~")
DB=f"{HOME}/.local/share/atuin/history.db"

# atuin: count + last per command-head
atuin_c=defaultdict(int); atuin_l=defaultdict(str)
rows=subprocess.run(["sqlite3","-separator","\t",DB,
  "SELECT command, datetime(MAX(timestamp)/1000000000,'unixepoch') FROM history GROUP BY command"],
  capture_output=True,text=True).stdout.splitlines()
# we only have grouped-by-full-command; re-derive head counts
res=subprocess.run(["sqlite3","-separator","\t",DB,"SELECT command, timestamp FROM history"],capture_output=True,text=True).stdout.splitlines()
import datetime
for line in res:
    if "\t" not in line: continue
    cmd,ts=line.rsplit("\t",1)
    head=cmd.strip().split()[0].split("/")[-1] if cmd.strip() else ""
    if not head: continue
    atuin_c[head]+=1
    try: d=datetime.datetime.utcfromtimestamp(int(ts)/1e9).strftime("%Y-%m-%d")
    except: d=""
    if d>atuin_l[head]: atuin_l[head]=d

# claude
cl_c=defaultdict(int); cl_l=defaultdict(str)
for r in csv.DictReader(open("/tmp/claude_tool_usage.csv")):
    cl_c[r["tool"]]+=int(r["count"]); 
    if r["last_used"][:10]>cl_l[r["tool"]]: cl_l[r["tool"]]=r["last_used"][:10]

# package->binary alias for known mismatches
alias={"go-task":"task","cilium-cli":"cilium","kubernetes-cli":"kubectl","kubernetes-cli@1.31":"kubectl",
       "git-delta":"delta","ripgrep":"rg","fd-find":"fd","python@3.14":"python3","openjdk":"java",
       "node@22":"node","gnu-sed":"sed","coreutils":"","bat":"bat"}
def usage(formula):
    b=alias.get(formula, formula)
    if not b: return (0,"")
    return (atuin_c.get(b,0)+cl_c.get(b,0), max(atuin_l.get(b,""),cl_l.get(b,"")))

# classify brew tools
brew=[l.split()[0] for l in open(f"{HOME}/scratch/devpod-migration/inventory/brew-list.txt") if l.strip()]
LIBHINT=("lib","@","-",) # not reliable; use a known library set instead
keep=[];drop=[];lib=[]
LIBS={"alsa-lib","cairo","freetype","glib","openssl@3","readline","sqlite","zlib","zlib-ng-compat","zstd","lz4",
 "ncurses","pcre2","libpng","jpeg-turbo","libtiff","webp","giflib","fontconfig","harfbuzz","graphite2","fribidi",
 "pixman","little-cms2","openjpeg","leptonica","gdbm","gmp","mpdecimal","oniguruma","berkeley-db@5","bzip2","xz",
 "expat","libffi","m4","perl","util-linux","krb5","keyutils","libcap","icu4c@78","icu4c@77","pango","gettext",
 "ca-certificates","certifi","openssl@1.1","libtool","libb2","libedit","libxcrypt","libsndfile","libogg","libvorbis",
 "flac","lame","mpg123","opus","speexdsp","libsamplerate","libsoxr","orc","jack","pulseaudio","portaudio","sdl2",
 "libx11","libxau","libxcb","libxdmcp","libxext","libxfixes","libxi","libxrandr","libxrender","libxt","libxtst",
 "libxcursor","libxscrnsaver","libsm","libice","xorgproto","cups","dbus","systemd","oniguruma","little-cms2"}
for f in brew:
    if f in LIBS: lib.append(f); continue
    n,last=usage(f)
    (keep if n>0 else drop).append((f,n,last))
keep.sort(key=lambda x:-x[1])
print("=== BREW: KEEP (used by you or Claude) ===")
for f,n,l in keep: print(f"  {f:<18} {n:>5}  {l}")
print(f"\n=== BREW: DROP candidates (0 invocations either side, not a known lib) — {len(drop)} ===")
print("  "+", ".join(f for f,_,_ in sorted(drop)))
print(f"\n=== BREW: libraries (keep by dependency, not usage) — {len(lib)} ===")
