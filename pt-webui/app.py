from fastapi import FastAPI, BackgroundTasks
from fastapi.responses import FileResponse, PlainTextResponse
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import List, Optional
import urllib.request
import subprocess
import os

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
        
        # 1. 更新前端 UI
        html_url = f"{base_url}/index.html"
        html_content = urllib.request.urlopen(html_url).read().decode('utf-8')
        with open("index.html", "w", encoding="utf-8") as f:
            f.write(html_content)

        # 2. 更新底层 Bash
        bash_url = f"{base_url}/pt_make_headless.sh"
        bash_content = urllib.request.urlopen(bash_url).read().decode('utf-8').replace('\r\n', '\n')
        with open("/app/pt_make_headless.sh", "w", encoding="utf-8", newline='\n') as f:
            f.write(bash_content)
        os.chmod("/app/pt_make_headless.sh", 0o755)

        # 3. 更新核心 Python
        app_url = f"{base_url}/app.py"
        app_content = urllib.request.urlopen(app_url).read().decode('utf-8')
        with open("/app/app.py", "w", encoding="utf-8") as f:
            f.write(app_content)

        # 4. 触发 Docker 重启
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
