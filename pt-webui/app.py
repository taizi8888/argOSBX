import os, time, json, shutil, subprocess, re
import urllib.request, urllib.parse
import concurrent.futures
from fastapi import FastAPI, BackgroundTasks, Request
from fastapi.responses import FileResponse, PlainTextResponse
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import List, Optional, Any

app = FastAPI()
BASE_DIR = os.getenv("BASE_DIR", "/downloads")
CONFIG_DIR = os.path.join(BASE_DIR, ".config")
CONFIG_FILE = os.path.join(CONFIG_DIR, "nodes.json")
TRAFFIC_FILE = os.path.join(CONFIG_DIR, "traffic.json")
LOG_FILE = os.path.join(CONFIG_DIR, "last_task.log")

os.makedirs(CONFIG_DIR, exist_ok=True)

app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_credentials=True, allow_methods=["*"], allow_headers=["*"])

class RunRequest(BaseModel):
    folder: str = ""
    tracker: Optional[str] = None
    piece_size: Optional[str] = None
    layout: Optional[str] = None
    overwrite_torrent: bool = False
    overwrite_image: bool = False

class BatchRequest(BaseModel):
    folders: List[str]

@app.get("/")
def index(): return FileResponse("index.html")

@app.get("/api/nodes")
def get_nodes():
    if os.path.exists(CONFIG_FILE):
        try:
            with open(CONFIG_FILE, "r", encoding="utf-8") as f: return json.load(f)
        except: pass
    return []

@app.post("/api/nodes")
def save_nodes(nodes: List[Any]):
    with open(CONFIG_FILE, "w", encoding="utf-8") as f: json.dump(nodes, f, ensure_ascii=False, indent=2)
    return {"status": "success"}

@app.get("/api/folders")
def list_folders():
    folders = []
    if os.path.exists(BASE_DIR):
        for item in os.listdir(BASE_DIR):
            if item.startswith("."): continue
            path = os.path.join(BASE_DIR, item)
            if os.path.isdir(path):
                has_torrent = os.path.exists(os.path.join(BASE_DIR, f"{item}.torrent"))
                has_img = os.path.exists(os.path.join(BASE_DIR, f"{item}_Stitched_4K.jpg"))
                ready = has_torrent and has_img
                status = "✅ 已完成" if ready else "⏳ 待处理"
                folders.append({"name": item, "status": status, "ready": ready, "mtime": os.path.getmtime(path)})
    folders.sort(key=lambda x: (x["ready"], -x["mtime"]))
    return {"folders": folders}

@app.get("/api/sysinfo")
def sysinfo():
    try:
        mem_path = '/host_proc/meminfo' if os.path.exists('/host_proc/meminfo') else '/proc/meminfo'
        with open(mem_path, 'r') as f: mem_lines = f.readlines()
        mem_total = int(mem_lines[0].split()[1]) * 1024
        mem_used = mem_total - int(mem_lines[2].split()[1]) * 1024
        stat_path = '/host_proc/stat' if os.path.exists('/host_proc/stat') else '/proc/stat'
        with open(stat_path, 'r') as f: cpu_line = f.readline().split()
        cpu_idle = float(cpu_line[4]) + float(cpu_line[5])
        cpu_total = sum(float(x) for x in cpu_line[1:8])
        net_tx, net_rx = 0, 0
        net_path = '/host_proc/1/net/dev' if os.path.exists('/host_proc/1/net/dev') else '/proc/net/dev'
        with open(net_path, 'r') as f:
            for line in f.readlines()[2:]:
                parts = line.split(':')
                if len(parts) == 2:
                    iface = parts[0].strip()
                    if iface != "lo" and not iface.startswith("docker") and not iface.startswith("veth"):
                        vals = parts[1].split()
                        net_rx += int(vals[0]); net_tx += int(vals[8])
        current_month = time.strftime("%Y-%m")
        traffic_data = {"month": current_month, "month_tx": 0, "month_rx": 0, "last_tx": 0, "last_rx": 0}
        if os.path.exists(TRAFFIC_FILE):
            try:
                with open(TRAFFIC_FILE, "r") as f: traffic_data.update(json.load(f))
            except: pass
        if traffic_data.get("month") != current_month:
            traffic_data["month"] = current_month; traffic_data["month_tx"] = 0; traffic_data["month_rx"] = 0
        dtx, drx = max(0, net_tx - traffic_data.get("last_tx", 0)), max(0, net_rx - traffic_data.get("last_rx", 0))
        traffic_data["month_tx"] += dtx; traffic_data["month_rx"] += drx
        traffic_data["last_tx"] = net_tx; traffic_data["last_rx"] = net_rx
        with open(TRAFFIC_FILE, "w") as f: json.dump(traffic_data, f)
        try:
            disk_usage = shutil.disk_usage(BASE_DIR)
            disk_total, disk_used = disk_usage.total, disk_usage.used
        except: disk_total, disk_used = 0, 0
        return { "mem_total": mem_total, "mem_used": mem_used, "cpu_idle": cpu_idle, "cpu_total": cpu_total, "net_tx": net_tx, "net_rx": net_rx, "month_tx": traffic_data["month_tx"], "month_rx": traffic_data["month_rx"], "disk_total": disk_total, "disk_used": disk_used, "timestamp": time.time() }
    except Exception as e: return {"error": str(e)}

@app.post("/api/qbittorrent")
def qbittorrent_proxy(req: dict):
    qb_url = req.get("url", "").rstrip("/"); action = req.get("action"); name = req.get("name", "")
    user = req.get("user", ""); pwd = req.get("pwd", "")
    if not qb_url: return {"error": "No QB URL"}
    cookie = ""
    if user:
        try:
            login_data = urllib.parse.urlencode({'username': user, 'password': pwd}).encode('utf-8')
            l_req = urllib.request.Request(f"{qb_url}/api/v2/auth/login", data=login_data)
            cookie = urllib.request.urlopen(l_req, timeout=5).headers.get('Set-Cookie').split(';')[0]
        except: return {"error": "QB Login Failed"}
    headers = {"Cookie": cookie} if cookie else {}
    try:
        if action == "list":
            r = urllib.request.Request(f"{qb_url}/api/v2/torrents/info", headers=headers)
            return json.loads(urllib.request.urlopen(r, timeout=5).read().decode('utf-8'))
        elif action in ["pause", "resume"]:
            data = urllib.parse.urlencode({'hashes': req.get('hashes', '')}).encode('utf-8')
            urllib.request.urlopen(urllib.request.Request(f"{qb_url}/api/v2/torrents/{action}", data=data, headers=headers), timeout=5)
            return {"status": "ok"}
        elif action == "delete":
            del_files = req.get('delete_files'); del_flag = "true" if del_files else "false"
            data = urllib.parse.urlencode({'hashes': req.get('hashes', ''), 'deleteFiles': del_flag}).encode('utf-8')
            urllib.request.urlopen(urllib.request.Request(f"{qb_url}/api/v2/torrents/delete", data=data, headers=headers), timeout=5)
            if del_files and name:
                for n in name.split("|"):
                    for ext in [".torrent", "_mediainfo.txt", "_Stitched_4K.jpg", "_ffmpeg_debug.log"]:
                        p = os.path.join(BASE_DIR, f"{n.strip()}{ext}"); 
                        if os.path.exists(p): os.remove(p)
            return {"status": "ok"}
    except Exception as e: return {"error": str(e)}

@app.post("/api/run/{mode}")
def run_task(mode: str, req: RunRequest, background_tasks: BackgroundTasks):
    def execute_script():
        if mode == "folder" and req.folder:
            if req.overwrite_image:
                for ext in ["_Stitched_4K.jpg", "_ffmpeg_debug.log"]:
                    p = os.path.join(BASE_DIR, f"{req.folder}{ext}")
                    if os.path.exists(p): os.remove(p)
            if req.overwrite_torrent:
                for ext in [".torrent", "_mediainfo.txt"]:
                    p = os.path.join(BASE_DIR, f"{req.folder}{ext}")
                    if os.path.exists(p): os.remove(p)
        cmd = ["/bin/bash", "/app/pt_make.sh", f"--{mode}"]
        if mode == "folder" and req.folder: cmd.append(req.folder)
        env = os.environ.copy()
        if req.tracker: env["CUSTOM_TRACKER"] = req.tracker
        if req.piece_size: env["CUSTOM_PIECE_L"] = str(req.piece_size)
        if req.layout: env["CUSTOM_LAYOUT"] = req.layout
        with open(LOG_FILE, "a") as f:
            f.write(f"\n[{time.strftime('%Y-%m-%d %H:%M:%S')}] RUNNING: {' '.join(cmd)}\n")
            f.flush(); os.fsync(f.fileno())
            subprocess.run(cmd, env=env, stdout=f, stderr=subprocess.STDOUT)
    background_tasks.add_task(execute_script)
    return {"message": "Task Started"}

@app.post("/api/run_batch")
def run_batch(req: BatchRequest, background_tasks: BackgroundTasks):
    def execute_batch():
        with open(LOG_FILE, "a") as f:
            f.write(f"\n[{time.strftime('%Y-%m-%d %H:%M:%S')}] RUNNING BATCH TASK\n")
            f.flush(); os.fsync(f.fileno())
            for folder in req.folders:
                subprocess.run(["/bin/bash", "/app/pt_make.sh", "--folder", folder], stdout=f, stderr=subprocess.STDOUT)
                f.flush()
    background_tasks.add_task(execute_batch)
    return {"message": "Batch Started"}

@app.get("/api/logs")
def get_logs():
    if os.path.exists(LOG_FILE):
        try:
            with open(LOG_FILE, "r", encoding="utf-8", errors="ignore") as f:
                lines = f.readlines()
                return {"logs": "".join(lines[-500:])}
        except Exception as e: return {"error": str(e)}
    return {"logs": "No logs yet."}

@app.post("/api/logs/clear")
def clear_logs():
    try:
        open(LOG_FILE, 'w').close()
        return {"status": "ok"}
    except Exception as e: return {"error": str(e)}


# V8.4 终极地毯式扫描：全频道并发直连 + DDG 代理兜底
@app.get("/api/scraper/{keyword}")
def scrape_link(keyword: str):
    keyword = keyword.strip().lower()
    headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8',
        'Accept-Language': 'ja,en-US;q=0.9,en;q=0.8'
    }

    def extract_dmm_link(raw_html):
        decoded_html = urllib.parse.unquote(raw_html)
        all_matches = re.findall(r'(https?://(?:[a-zA-Z0-9-]+\.)?(?:dmm|fanza)\.co\.jp/[^\s"\'<>]+)', decoded_html)
        
        for raw_link in all_matches:
            if "pics.dmm.co.jp" in raw_link or "book.dmm.co.jp" in raw_link or "games.dmm.co.jp" in raw_link or raw_link.endswith(('.jpg', '.jpeg', '.png', '.gif')):
                continue
                
            candidate_link = raw_link
            if "lurl=" in raw_link:
                try:
                    lurl_encoded = raw_link.split("lurl=")[1].split("&")[0]
                    candidate_link = urllib.parse.unquote(lurl_encoded)
                except Exception:
                    pass

            candidate_link = candidate_link.split('"')[0].split("'")[0].split('<')[0]
            is_product = any(x in candidate_link for x in ["/detail/", "?id=", "&id=", "?cid=", "&cid="])
            
            if is_product:
                if "campaign" not in candidate_link and "/list/" not in candidate_link and "article" not in candidate_link:
                    return candidate_link
        return None

    def fetch_url(url):
        try:
            req = urllib.request.Request(url, headers=headers)
            html = urllib.request.urlopen(req, timeout=4).read().decode('utf-8', errors='ignore')
            return extract_dmm_link(html)
        except Exception:
            return None

    # 第一波攻势：Wiki 全频道火力覆盖 (直连极速)
    # 不管它是素人、MGS、FC2还是正规车牌，全部打出去！只有一个会存活(200 OK)
    wiki_targets = [
        f"https://shiroutowiki.work/fanza-video/{keyword}/",
        f"https://shiroutowiki.work/fanza-amateur/{keyword}/",
        f"https://shiroutowiki.work/fc2/{keyword}/",
        f"https://shiroutowiki.work/mgs/{keyword}/",
        f"https://shiroutowiki.work/{keyword}/"
    ]

    with concurrent.futures.ThreadPoolExecutor(max_workers=5) as executor:
        future_to_url = {executor.submit(fetch_url, url): url for url in wiki_targets}
        # 既然是精确 URL 探测，不会有脏搜索结果，谁先返回谁就绝对是真理！
        for future in concurrent.futures.as_completed(future_to_url):
            result = future.result()
            if result:
                return {"link": result}

    # 第二波攻势：DuckDuckGo 代理兜底 (如果 Wiki 彻底没收录)
    # 必须套 AllOrigins 代理，防止连刷导致甲骨文 IP 被 DDG 封禁
    try:
        ddg_query = urllib.parse.quote(f"{keyword} site:shiroutowiki.work OR site:dmm.co.jp")
        ddg_url = f"https://html.duckduckgo.com/html/?q={ddg_query}&kp=-2"
        proxy_url = f"https://api.allorigins.win/get?url={urllib.parse.quote(ddg_url)}"
        
        req = urllib.request.Request(proxy_url, headers=headers)
        resp = urllib.request.urlopen(req, timeout=6).read().decode('utf-8', errors='ignore')
        html = json.loads(resp).get("contents", "")
        link = extract_dmm_link(html)
        if link: 
            return {"link": link}
    except Exception:
        pass

    return {"error": "全域频段并发检索未能命中，请使用【🌐 浏览器搜索】"}

@app.post("/api/update")
def update_system(background_tasks: BackgroundTasks):
    def execute_ota():
        time.sleep(1)
        try:
            base_url = "https://raw.githubusercontent.com/taizi8888/argOSBX/shdetai/pt-webui"
            for f_name in ["index.html", "app.py", "pt_make.sh"]:
                url = f"{base_url}/{f_name}"
                req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
                content = urllib.request.urlopen(req, timeout=15).read().decode('utf-8')
                write_path = f"/app/{f_name}" if os.path.exists("/app") else f_name
                with open(write_path, "w", encoding="utf-8") as f: f.write(content)
            script_path = "/app/pt_make.sh" if os.path.exists("/app/pt_make.sh") else "pt_make.sh"
            if os.path.exists(script_path): os.chmod(script_path, 0o755)
            with open(LOG_FILE, "a") as f:
                f.write(f"\n[{time.strftime('%Y-%m-%d %H:%M:%S')}] OTA Rebirth Triggered (shdetai)\n")
                f.flush(); os.fsync(f.fileno())
            time.sleep(2); os._exit(0) 
        except Exception as e:
            with open(LOG_FILE, "a") as f: f.write(f"\nOTA FAILED: {str(e)}\n"); f.flush()
    background_tasks.add_task(execute_ota)
    return {"message": "Update Triggered"}

@app.get("/api/files/{folder}/{file_type}")
def download_file(folder: str, file_type: str):
    exts = {"torrent": ".torrent", "mediainfo": "_mediainfo.txt", "image": "_Stitched_4K.jpg"}
    p = os.path.join(BASE_DIR, f"{folder}{exts.get(file_type, '')}")
    if os.path.exists(p): return FileResponse(p, filename=os.path.basename(p))
    return {"error": "Not Found"}

@app.get("/api/preview/mediainfo/{folder}")
def preview_mediainfo(folder: str):
    p = os.path.join(BASE_DIR, f"{folder}_mediainfo.txt")
    if os.path.exists(p):
        with open(p, "r", encoding="utf-8", errors="ignore") as f: return PlainTextResponse(f.read())
    return PlainTextResponse("Not Found")
