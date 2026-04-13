from fastapi import FastAPI, BackgroundTasks
from fastapi.responses import FileResponse, PlainTextResponse
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import List, Optional, Any
import urllib.request
import urllib.parse
import subprocess
import os
import time
import json

app = FastAPI()
BASE_DIR = os.getenv("BASE_DIR", "/downloads")
CONFIG_FILE = os.path.join(BASE_DIR, ".config", "nodes.json")
TRAFFIC_FILE = os.path.join(BASE_DIR, ".config", "traffic.json")

# ================= 集群核心设置 =================
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
# ===============================================

class RunRequest(BaseModel):
    folder: str = ""
    tracker: Optional[str] = None
    piece_size: Optional[str] = None
    layout: Optional[str] = None

class BatchRequest(BaseModel):
    folders: List[str]

@app.get("/")
def index():
    return FileResponse("index.html")

# ================= 集群节点云端持久化 API =================
@app.get("/api/nodes")
def get_nodes():
    if os.path.exists(CONFIG_FILE):
        try:
            with open(CONFIG_FILE, "r", encoding="utf-8") as f:
                return json.load(f)
        except:
            pass
    return []

@app.post("/api/nodes")
def save_nodes(nodes: List[Any]):
    os.makedirs(os.path.dirname(CONFIG_FILE), exist_ok=True)
    with open(CONFIG_FILE, "w", encoding="utf-8") as f:
        json.dump(nodes, f, ensure_ascii=False, indent=2)
    return {"status": "success"}

# ================= 业务接口 =================
@app.get("/api/folders")
def list_folders():
    folders = []
    if os.path.exists(BASE_DIR):
        for item in os.listdir(BASE_DIR):
            if item.startswith("."):
                continue
            path = os.path.join(BASE_DIR, item)
            if os.path.isdir(path):
                has_torrent = os.path.exists(os.path.join(BASE_DIR, f"{item}.torrent"))
                has_img = os.path.exists(os.path.join(BASE_DIR, f"{item}_Stitched_4K.jpg"))
                ready = has_torrent and has_img
                status = "✅ 已完成" if ready else "⏳ 待处理"
                mtime = os.path.getmtime(path)
                folders.append({"name": item, "status": status, "ready": ready, "mtime": mtime})
                
    folders.sort(key=lambda x: (x["ready"], -x["mtime"]))
    return {"folders": folders}

# ================= Nezha 探针级硬件监控 =================
@app.get("/api/sysinfo")
def sysinfo():
    try:
        mem_path = '/host_proc/meminfo' if os.path.exists('/host_proc/meminfo') else '/proc/meminfo'
        with open(mem_path, 'r') as f:
            mem_lines = f.readlines()
        mem_total = int(mem_lines[0].split()[1]) * 1024
        mem_available = int(mem_lines[2].split()[1]) * 1024
        mem_used = mem_total - mem_available

        stat_path = '/host_proc/stat' if os.path.exists('/host_proc/stat') else '/proc/stat'
        with open(stat_path, 'r') as f:
            cpu_line = f.readline().split()
        cpu_idle = float(cpu_line[4]) + float(cpu_line[5])
        cpu_total = sum(float(x) for x in cpu_line[1:8])

        net_tx, net_rx = 0, 0
        if os.path.exists('/host_proc/1/net/dev'):
            net_path = '/host_proc/1/net/dev'
        elif os.path.exists('/host_proc/net/dev'):
            net_path = '/host_proc/net/dev'
        else:
            net_path = '/proc/net/dev'
            
        with open(net_path, 'r') as f:
            for line in f.readlines()[2:]:
                parts = line.split(':')
                if len(parts) == 2:
                    iface = parts[0].strip()
                    if iface != "lo" and not iface.startswith("docker") and not iface.startswith("veth") and not iface.startswith("br-"):
                        vals = parts[1].split()
                        net_rx += int(vals[0])
                        net_tx += int(vals[8])

        current_month = time.strftime("%Y-%m")
        traffic_data = {"month": current_month, "month_tx": 0, "month_rx": 0, "last_tx": 0, "last_rx": 0}
        
        if os.path.exists(TRAFFIC_FILE):
            try:
                with open(TRAFFIC_FILE, "r") as f:
                    saved_data = json.load(f)
                    traffic_data.update(saved_data)
            except: pass

        if traffic_data.get("month") != current_month:
            traffic_data["month"] = current_month
            traffic_data["month_tx"] = 0
            traffic_data["month_rx"] = 0

        delta_tx = net_tx - traffic_data.get("last_tx", 0)
        delta_rx = net_rx - traffic_data.get("last_rx", 0)

        if delta_tx < 0: delta_tx = net_tx
        if delta_rx < 0: delta_rx = net_rx

        traffic_data["month_tx"] += delta_tx
        traffic_data["month_rx"] += delta_rx
        traffic_data["last_tx"] = net_tx
        traffic_data["last_rx"] = net_rx

        os.makedirs(os.path.dirname(TRAFFIC_FILE), exist_ok=True)
        with open(TRAFFIC_FILE, "w") as f:
            json.dump(traffic_data, f)

        return {
            "mem_total": mem_total, "mem_used": mem_used, "cpu_idle": cpu_idle, "cpu_total": cpu_total,
            "net_tx": net_tx, "net_rx": net_rx, "month_tx": traffic_data["month_tx"], "month_rx": traffic_data["month_rx"],
            "timestamp": time.time()
        }
    except Exception as e:
        return {"error": str(e)}

# ================= qBittorrent API 代理透传 & 批量深度清理 =================
@app.post("/api/qbittorrent")
def qbittorrent_proxy(req: dict):
    qb_url = req.get("url", "").rstrip("/")
    action = req.get("action")
    name = req.get("name", "")
    user = req.get("user", "")
    pwd = req.get("pwd", "")
    
    if not qb_url: return {"error": "未提供 qBittorrent 地址"}
    
    cookie = ""
    if user:
        try:
            login_data = urllib.parse.urlencode({'username': user, 'password': pwd}).encode('utf-8')
            l_req = urllib.request.Request(f"{qb_url}/api/v2/auth/login", data=login_data)
            l_resp = urllib.request.urlopen(l_req, timeout=5)
            cookie_header = l_resp.headers.get('Set-Cookie')
            if cookie_header:
                cookie = cookie_header.split(';')[0]
        except Exception as e:
            return {"error": f"qBittorrent 登录失败: {str(e)}"}
            
    headers = {"Cookie": cookie} if cookie else {}
    
    try:
        if action == "list":
            r = urllib.request.Request(f"{qb_url}/api/v2/torrents/info", headers=headers)
            resp = urllib.request.urlopen(r, timeout=5)
            return json.loads(resp.read().decode('utf-8'))
            
        elif action in ["pause", "resume"]:
            data = urllib.parse.urlencode({'hashes': req.get('hashes', '')}).encode('utf-8')
            r = urllib.request.Request(f"{qb_url}/api/v2/torrents/{action}", data=data, headers=headers)
            urllib.request.urlopen(r, timeout=5)
            return {"status": "ok"}
            
        elif action == "delete":
            del_files = req.get('delete_files')
            del_flag = "true" if del_files else "false"
            # 下发删除请求 (支持 hashes 被 | 分隔，进行批量删除)
            data = urllib.parse.urlencode({'hashes': req.get('hashes', ''), 'deleteFiles': del_flag}).encode('utf-8')
            r = urllib.request.Request(f"{qb_url}/api/v2/torrents/delete", data=data, headers=headers)
            urllib.request.urlopen(r, timeout=5)
            
            # 【核心逻辑升级】：支持批量任务名称解析，进行深度强迫症清理
            if del_files and name:
                names_list = name.split("|") # 支持前端传过来的 | 分隔的多任务名
                garbage_extensions = [".torrent", "_mediainfo.txt", "_Stitched_4K.jpg", "_ffmpeg_debug.log"]
                
                for n in names_list:
                    n = n.strip()
                    if not n: continue
                    for ext in garbage_extensions:
                        garbage_path = os.path.join(BASE_DIR, f"{n}{ext}")
                        if os.path.exists(garbage_path):
                            try: os.remove(garbage_path)
                            except: pass
            
            return {"status": "ok"}
            
        else: return {"error": "未知的执行指令"}
            
    except Exception as e:
        return {"error": f"qB API 请求失败: 请检查 IP、端口或账号密码 ({str(e)})"}

@app.post("/api/run/{mode}")
def run_task(mode: str, req: RunRequest, background_tasks: BackgroundTasks):
    def execute_script():
        cmd = ["/bin/bash", "/app/pt_make_headless.sh", f"--{mode}"]
        if mode == "folder" and req.folder: cmd.append(req.folder)
        env = os.environ.copy()
        if req.tracker: env["CUSTOM_TRACKER"] = req.tracker
        if req.piece_size: env["CUSTOM_PIECE_L"] = req.piece_size
        if req.layout: env["CUSTOM_LAYOUT"] = req.layout
        subprocess.run(cmd, env=env)
    background_tasks.add_task(execute_script)
    return {"message": "任务已在后台启动！"}

@app.post("/api/run_batch")
def run_batch(req: BatchRequest, background_tasks: BackgroundTasks):
    def execute_batch():
        for folder in req.folders:
            subprocess.run(["/bin/bash", "/app/pt_make_headless.sh", "--folder", folder])
    background_tasks.add_task(execute_batch)
    return {"message": "批量任务已启动！"}

@app.post("/api/update")
def update_system(background_tasks: BackgroundTasks):
    try:
        base_url = "https://raw.githubusercontent.com/taizi8888/argOSBX/main/pt-webui"
        
        html_url = f"{base_url}/index.html"
        html_content = urllib.request.urlopen(html_url).read().decode('utf-8')
        with open("index.html", "w", encoding="utf-8") as f: f.write(html_content)

        bash_url = f"{base_url}/pt_make_headless.sh"
        bash_content = urllib.request.urlopen(bash_url).read().decode('utf-8').replace('\r\n', '\n')
        with open("/app/pt_make_headless.sh", "w", encoding="utf-8", newline='\n') as f: f.write(bash_content)
        os.chmod("/app/pt_make_headless.sh", 0o755)

        app_url = f"{base_url}/app.py"
        app_content = urllib.request.urlopen(app_url).read().decode('utf-8')
        with open("/app/app.py", "w", encoding="utf-8") as f: f.write(app_content)

        def restart_server():
            time.sleep(2)
            os._exit(0) 
            
        background_tasks.add_task(restart_server)
        return {"message": "✅ OTA 全量升级包已覆盖！\n前端已更新，后端容器将在 2 秒后自动重启重生，请稍后刷新网页。"}
        
    except Exception as e:
        return {"message": f"❌ OTA 升级失败: {str(e)}\n请检查网络或 GitHub 路径。"}

@app.get("/api/files/{folder}/{file_type}")
def download_file(folder: str, file_type: str):
    if file_type == "torrent": file_path = os.path.join(BASE_DIR, f"{folder}.torrent")
    elif file_type == "mediainfo": file_path = os.path.join(BASE_DIR, f"{folder}_mediainfo.txt")
    elif file_type == "image": file_path = os.path.join(BASE_DIR, f"{folder}_Stitched_4K.jpg")
    else: return {"error": "未知的格式"}
    if os.path.exists(file_path): return FileResponse(file_path, filename=os.path.basename(file_path))
    return {"error": "文件不存在"}

@app.get("/api/preview/mediainfo/{folder}")
def preview_mediainfo(folder: str):
    file_path = os.path.join(BASE_DIR, f"{folder}_mediainfo.txt")
    if os.path.exists(file_path):
        with open(file_path, "r", encoding="utf-8", errors="ignore") as f: return PlainTextResponse(f.read())
    return PlainTextResponse("数据不存在或正在生成中...")
