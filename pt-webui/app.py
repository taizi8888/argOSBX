from fastapi import FastAPI, BackgroundTasks
from fastapi.responses import FileResponse, PlainTextResponse
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import List, Optional
import urllib.request
import subprocess
import os
import time

app = FastAPI()
BASE_DIR = os.getenv("BASE_DIR", "/downloads")

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

# ================= 新增：Nezha 探针级硬件监控 =================
@app.get("/api/sysinfo")
def sysinfo():
    try:
        # 1. 提取内存信息
        with open('/proc/meminfo', 'r') as f:
            mem_lines = f.readlines()
        mem_total = int(mem_lines[0].split()[1]) * 1024
        mem_available = int(mem_lines[2].split()[1]) * 1024
        mem_used = mem_total - mem_available

        # 2. 提取 CPU 滴答数
        with open('/proc/stat', 'r') as f:
            cpu_line = f.readline().split()
        cpu_idle = float(cpu_line[4]) + float(cpu_line[5])
        cpu_total = sum(float(x) for x in cpu_line[1:8])

        # 3. 提取网卡实时流量
        net_tx, net_rx = 0, 0
        with open('/proc/net/dev', 'r') as f:
            for line in f.readlines()[2:]:
                parts = line.split(':')
                if len(parts) == 2 and parts[0].strip() != "lo":
                    vals = parts[1].split()
                    net_rx += int(vals[0])
                    net_tx += int(vals[8])

        return {
            "mem_total": mem_total,
            "mem_used": mem_used,
            "cpu_idle": cpu_idle,
            "cpu_total": cpu_total,
            "net_tx": net_tx,
            "net_rx": net_rx,
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

# ================= OTA 全量自杀式热更新引擎 =================
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
            import time
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
