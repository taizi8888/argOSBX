import os, time, json, shutil, subprocess
import urllib.request, urllib.parse
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
