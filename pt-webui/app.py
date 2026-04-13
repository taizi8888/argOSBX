from fastapi import FastAPI, BackgroundTasks
from fastapi.responses import FileResponse, PlainTextResponse
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import List, Optional, Any
import urllib.request
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

# ================= Nezha 探针级硬件监控 (新增按月流量统计) =================
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

        # --- 核心：按月流量累计算法 (防重启丢失) ---
        current_month = time.strftime("%Y-%m")
        traffic_data = {"month": current_month, "month_tx": 0, "month_rx": 0, "last_tx": 0, "last_rx": 0}
        
        if os.path.exists(TRAFFIC_FILE):
            try:
                with open(TRAFFIC_FILE, "r") as f:
                    saved_data = json.load(f)
                    traffic_data.update(saved_data)
            except: pass

        # 检查是否跨月，跨月清零
        if traffic_data.get("month") != current_month:
            traffic_data["month"] = current_month
            traffic_data["month_tx"] = 0
            traffic_data["month_rx"] = 0

        # 计算增量流量 (防 Linux 重启导致计数器归零)
        delta_tx = net_tx - traffic_data.get("last_tx", 0)
        delta_rx = net_rx - traffic_data.get("last_rx", 0)

        if delta_tx < 0: delta_tx = net_tx
        if delta_rx < 0: delta_rx = net_rx

        traffic_data["month_tx"] += delta_tx
        traffic_data["month_rx"] += delta_rx
        traffic_data["last_tx"] = net_tx
        traffic_data["last_rx"] = net_rx

        # 持久化保存
        os.makedirs(os.path.dirname(TRAFFIC_FILE), exist_ok=True)
        with open(TRAFFIC_FILE, "w") as f:
            json.dump(traffic_data, f)
        # ------------------------------------------

        return {
            "mem_total": mem_total,
            "mem_used": mem_used,
            "cpu_idle": cpu_idle,
            "cpu_total": cpu_total,
            "net_tx": net_tx,
            "net_rx": net_rx,
            "month_tx": traffic_data["month_tx"],  # 传出本月累计发送
            "month_rx": traffic_data["month_rx"],  # 传出本月累计接收
            "timestamp": time.time()
        }
    except Exception as e:
        return {"error": str(e)}

@app.post("/api/run/{mode}")
def run_task(mode: str, req: RunRequest, background_tasks: BackgroundTasks):
    def execute_script():
        cmd = ["/bin/bash", "/app/pt_make_headless.sh", f"--{mode}"]
        if mode == "folder" and req.folder:
            cmd.append(req.folder)
            
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
    if file_type == "torrent":
        file_path = os.path.join(BASE_DIR, f"{folder}.torrent")
        media_type = "application/x-bittorrent"
    elif file_type == "mediainfo":
        file_path = os.path.join(BASE_DIR, f"{folder}_mediainfo.txt")
        media_type = "text/plain"
    elif file_type == "image":
        file_path = os.path.join(BASE_DIR, f"{folder}_Stitched_4K.jpg")
        media_type = "image/jpeg"
    else: return {"error": "未知的格式"}

    if os.path.exists(file_path):
        return FileResponse(file_path, media_type=media_type, filename=os.path.basename(file_path))
    return {"error": "文件不存在"}

@app.get("/api/preview/mediainfo/{folder}")
def preview_mediainfo(folder: str):
    file_path = os.path.join(BASE_DIR, f"{folder}_mediainfo.txt")
    if os.path.exists(file_path):
        with open(file_path, "r", encoding="utf-8", errors="ignore") as f:
            return PlainTextResponse(f.read())
    return PlainTextResponse("数据不存在或正在生成中...")
