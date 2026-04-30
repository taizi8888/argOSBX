import os, time, json, shutil, subprocess, re
import urllib.request, urllib.parse
import concurrent.futures
import html
from fastapi import FastAPI, BackgroundTasks, Request
from fastapi.responses import FileResponse, PlainTextResponse
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import List, Optional, Any

app = FastAPI()
BASE_DIR = os.getenv("BASE_DIR", "/downloads")
if not os.path.exists(BASE_DIR):
    if os.path.exists("/vol3/1000/downloads"): BASE_DIR = "/vol3/1000/downloads"
    else: BASE_DIR = "/home/docker/qbittorrent/downloads"

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
    enable_gif: bool = True

class BatchRequest(BaseModel):
    folders: List[str]
    enable_gif: bool = True
    overwrite_torrent: bool = False
    overwrite_image: bool = False

def get_base_name(target_name: str) -> str:
    p = os.path.join(BASE_DIR, target_name)
    if os.path.isfile(p):
        return os.path.splitext(target_name)[0]
    return target_name

@app.get("/")
def index(): 
    idx_path = "/home/taizi8888/index.html"
    if os.path.exists(idx_path): return FileResponse(idx_path)
    return FileResponse("index.html")

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
            
            is_valid = False
            if os.path.isdir(path):
                is_valid = True
            elif os.path.isfile(path) and item.lower().endswith(('.mp4', '.mkv', '.avi', '.wmv', '.ts')):
                is_valid = True
                
            if is_valid:
                base_name = get_base_name(item)
                has_torrent = os.path.exists(os.path.join(BASE_DIR, f"{base_name}.torrent"))
                has_img = os.path.exists(os.path.join(BASE_DIR, f"{base_name}_Stitched_4K.jpg"))
                has_gif = os.path.exists(os.path.join(BASE_DIR, f"{base_name}_Preview.gif"))
                ready = has_torrent and has_img
                status = "✅ 已完成" if ready else "⏳ 待处理"
                folders.append({"name": item, "status": status, "ready": ready, "has_gif": has_gif, "mtime": os.path.getmtime(path)})
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
                    base_name = get_base_name(n.strip())
                    for ext in [".torrent", "_mediainfo.txt", "_Stitched_4K.jpg", "_ffmpeg_debug.log", "_Preview.gif"]:
                        p = os.path.join(BASE_DIR, f"{base_name}{ext}")
                        if os.path.exists(p): os.remove(p)
            return {"status": "ok"}
    except Exception as e: return {"error": str(e)}

@app.post("/api/run/{mode}")
def run_task(mode: str, req: RunRequest, background_tasks: BackgroundTasks):
    def execute_script():
        script_path = "/home/taizi8888/pt_make.sh" if os.path.exists("/home/taizi8888/pt_make.sh") else ("/app/pt_make.sh" if os.path.exists("/app/pt_make.sh") else "/root/argosbx-web/pt-webui/pt_make.sh")
        if mode == "folder" and req.folder:
            base_name = get_base_name(req.folder)
            if req.overwrite_image:
                for ext in ["_Stitched_4K.jpg", "_ffmpeg_debug.log", "_Preview.gif"]:
                    p = os.path.join(BASE_DIR, f"{base_name}{ext}")
                    if os.path.exists(p): os.remove(p)
            if req.overwrite_torrent:
                for ext in [".torrent", "_mediainfo.txt"]:
                    p = os.path.join(BASE_DIR, f"{base_name}{ext}")
                    if os.path.exists(p): os.remove(p)
        cmd = ["/bin/bash", script_path, f"--{mode}"]
        if mode == "folder" and req.folder: cmd.append(req.folder)
        env = os.environ.copy()
        if req.tracker: env["CUSTOM_TRACKER"] = req.tracker
        if req.piece_size: env["CUSTOM_PIECE_L"] = str(req.piece_size)
        if req.layout: env["CUSTOM_LAYOUT"] = req.layout
        env["CUSTOM_ENABLE_GIF"] = "true" if req.enable_gif else "false"
        with open(LOG_FILE, "a") as f:
            f.write(f"\n[{time.strftime('%Y-%m-%d %H:%M:%S')}] RUNNING: {' '.join(cmd)}\n")
            f.flush(); os.fsync(f.fileno())
            subprocess.run(cmd, env=env, stdout=f, stderr=subprocess.STDOUT)
    background_tasks.add_task(execute_script)
    return {"message": "Task Started"}

@app.post("/api/run_batch")
def run_batch(req: BatchRequest, background_tasks: BackgroundTasks):
    def execute_batch():
        script_path = "/home/taizi8888/pt_make.sh" if os.path.exists("/home/taizi8888/pt_make.sh") else ("/app/pt_make.sh" if os.path.exists("/app/pt_make.sh") else "/root/argosbx-web/pt-webui/pt_make.sh")
        env = os.environ.copy()
        env["CUSTOM_ENABLE_GIF"] = "true" if req.enable_gif else "false"
        with open(LOG_FILE, "a") as f:
            f.write(f"\n[{time.strftime('%Y-%m-%d %H:%M:%S')}] RUNNING BATCH TASK\n")
            f.flush(); os.fsync(f.fileno())
            for folder in req.folders:
                base_name = get_base_name(folder)
                if req.overwrite_image:
                    for ext in ["_Stitched_4K.jpg", "_ffmpeg_debug.log", "_Preview.gif"]:
                        p = os.path.join(BASE_DIR, f"{base_name}{ext}")
                        if os.path.exists(p): os.remove(p)
                if req.overwrite_torrent:
                    for ext in [".torrent", "_mediainfo.txt"]:
                        p = os.path.join(BASE_DIR, f"{base_name}{ext}")
                        if os.path.exists(p): os.remove(p)
                subprocess.run(["/bin/bash", script_path, "--folder", folder], env=env, stdout=f, stderr=subprocess.STDOUT)
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

@app.get("/api/scraper/{keyword}")
def scrape_link(keyword: str):
    keyword = keyword.strip().lower()
    headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8'
    }

    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    
    custom_proxy = os.getenv("PROXY_HOST")
    proxy_url = custom_proxy or os.getenv("HTTPS_PROXY") or os.getenv("HTTP_PROXY")
    
    if proxy_url:
        proxies = {'http': proxy_url, 'https': proxy_url}
    else:
        proxies = urllib.request.getproxies()

    opener_direct = urllib.request.build_opener(urllib.request.HTTPSHandler(context=ctx))
    opener_proxy = urllib.request.build_opener(urllib.request.ProxyHandler(proxies), urllib.request.HTTPSHandler(context=ctx)) if proxies else opener_direct

    def is_strict_match(link: str, kw: str):
        m = re.search(r'(?:cid=|id=)([a-z0-9]+)', link.lower())
        if not m: return False
        cid = m.group(1)
        letters = re.sub(r'[^a-z]', '', kw.lower())
        numbers = re.sub(r'[^0-9]', '', kw)
        if not numbers: return True
        if numbers not in cid:
            num_stripped = numbers.lstrip('0')
            if not num_stripped or num_stripped not in cid: return False
        if len(letters) >= 2 and letters[:2] not in cid: return False
        return True

    def extract_dmm_link(raw_html, kw):
        if not raw_html: return None
        raw_html = html.unescape(raw_html)
        decoded_html = urllib.parse.unquote(raw_html)
        all_matches = re.findall(r'(https?://(?:[a-zA-Z0-9-]+\.)?(?:dmm|fanza)\.co\.jp/[^\s"\'<>]+)', decoded_html)
        
        for raw_link in all_matches:
            if "pics.dmm.co.jp" in raw_link or "book.dmm.co.jp" in raw_link or "games.dmm.co.jp" in raw_link or "article" in raw_link or raw_link.endswith(('.jpg', '.png', '.gif')):
                continue
                
            candidate_link = raw_link
            if "lurl=" in raw_link:
                try: candidate_link = urllib.parse.unquote(raw_link.split("lurl=")[1].split("&")[0])
                except: pass

            candidate_link = candidate_link.split('"')[0].split("'")[0].split('<')[0]
            clean = candidate_link.split('?af_id')[0].split('&af_id')[0].split('&ch=')[0]
            is_product = any(x in clean for x in ["/detail/", "?id=", "&id=", "?cid=", "&cid="])
            
            if is_product and "campaign" not in clean and "/list/" not in clean:
                if is_strict_match(clean, kw):
                    m = re.search(r'(?:cid=|id=)([a-z0-9]+)', clean.lower())
                    if m: return f"https://www.dmm.co.jp/mono/dvd/-/detail/=/cid={m.group(1)}/"
        return None

    def fetch_direct(target_url):
        try:
            req = urllib.request.Request(target_url, headers=headers)
            res_html = opener_proxy.open(req, timeout=3).read().decode('utf-8', errors='ignore')
            return extract_dmm_link(res_html, keyword)
        except: return None

    def fetch_via_codetabs(target_url):
        try:
            proxy = f"https://api.codetabs.com/v1/proxy/?quest={urllib.parse.quote(target_url)}"
            req = urllib.request.Request(proxy, headers=headers)
            res_html = opener_proxy.open(req, timeout=10).read().decode('utf-8', errors='ignore')
            return extract_dmm_link(res_html, keyword)
        except: return None

    def fetch_via_allorigins(target_url):
        try:
            proxy = f"https://api.allorigins.win/get?url={urllib.parse.quote(target_url)}"
            req = urllib.request.Request(proxy, headers=headers)
            resp = opener_proxy.open(req, timeout=10).read().decode('utf-8', errors='ignore')
            res_html = json.loads(resp).get("contents", "")
            return extract_dmm_link(res_html, keyword)
        except: return None

    kw_clean = keyword.replace("-", "").lower()
    wiki_search_urls = [f"https://shiroutowiki.work/?s={keyword}", f"https://shiroutowiki.work/{kw_clean}/"]
    javbus_urls = [f"https://www.javbus.com/{keyword}", f"https://www.javbus.com/{kw_clean}"]

    futures = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as executor:
        for w_url in wiki_search_urls:
            futures.append(executor.submit(fetch_direct, w_url))
            futures.append(executor.submit(fetch_via_codetabs, w_url))
            futures.append(executor.submit(fetch_via_allorigins, w_url))
        for j_url in javbus_urls:
            futures.append(executor.submit(fetch_via_codetabs, j_url))
            futures.append(executor.submit(fetch_via_allorigins, j_url))

        for future in concurrent.futures.as_completed(futures):
            res = future.result()
            if res: return {"link": res}

    return {"error": "全路并发检索未命中，该番号可能未被收录或下架，请使用【🌐 浏览器搜索】"}

@app.post("/api/update")
def update_system(background_tasks: BackgroundTasks):
    def execute_ota():
        time.sleep(1)
        try:
            custom_proxy = os.getenv("PROXY_HOST")
            if custom_proxy:
                opener = urllib.request.build_opener(urllib.request.ProxyHandler({'http': custom_proxy, 'https': custom_proxy}))
            else:
                opener = urllib.request.build_opener()
                
            base_url = "https://raw.githubusercontent.com/taizi8888/argOSBX/shdetai/pt-webui"
            for f_name in ["index.html", "app.py", "pt_make.sh"]:
                # 【核心防御】: 追加时间戳，彻底击穿 GitHub 的 5 分钟 CDN 缓存！
                url = f"{base_url}/{f_name}?t={int(time.time())}"
                req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0', 'Cache-Control': 'no-cache'})
                content = opener.open(req, timeout=15).read().decode('utf-8')
                write_path = f"/home/taizi8888/{f_name}" if os.path.exists("/home/taizi8888") else (f"/app/{f_name}" if os.path.exists("/app") else f"/root/argosbx-web/pt-webui/{f_name}")
                with open(write_path, "w", encoding="utf-8") as f: f.write(content)
            
            script_path = "/home/taizi8888/pt_make.sh" if os.path.exists("/home/taizi8888/pt_make.sh") else ("/app/pt_make.sh" if os.path.exists("/app/pt_make.sh") else "/root/argosbx-web/pt-webui/pt_make.sh")
            if os.path.exists(script_path): os.chmod(script_path, 0o755)
            
            with open(LOG_FILE, "a") as f:
                f.write(f"\n[{time.strftime('%Y-%m-%d %H:%M:%S')}] OTA Rebirth Triggered (shdetai) - Cache Bypassed\n")
                f.flush(); os.fsync(f.fileno())
            time.sleep(2); os._exit(0) 
        except Exception as e:
            with open(LOG_FILE, "a") as f: f.write(f"\nOTA FAILED: {str(e)}\n"); f.flush()
    background_tasks.add_task(execute_ota)
    return {"message": "Update Triggered"}

@app.get("/api/files/{folder}/{file_type}")
def download_file(folder: str, file_type: str):
    base_name = get_base_name(folder)
    exts = {"torrent": ".torrent", "mediainfo": "_mediainfo.txt", "image": "_Stitched_4K.jpg", "gif": "_Preview.gif"}
    p = os.path.join(BASE_DIR, f"{base_name}{exts.get(file_type, '')}")
    if os.path.exists(p): return FileResponse(p, filename=os.path.basename(p))
    return {"error": "Not Found"}

@app.get("/api/preview/mediainfo/{folder}")
def preview_mediainfo(folder: str):
    base_name = get_base_name(folder)
    p = os.path.join(BASE_DIR, f"{base_name}_mediainfo.txt")
    if os.path.exists(p):
        with open(p, "r", encoding="utf-8", errors="ignore") as f: return PlainTextResponse(f.read())
    return PlainTextResponse("Not Found")
