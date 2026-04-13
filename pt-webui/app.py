from fastapi import FastAPI, BackgroundTasks
from fastapi.responses import FileResponse, PlainTextResponse
from pydantic import BaseModel
from typing import List, Optional
import urllib.request
import subprocess
import os

app = FastAPI()
BASE_DIR = os.getenv("BASE_DIR", "/downloads")

# 定义数据结构
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
        for item in sorted(os.listdir(BASE_DIR)):
            path = os.path.join(BASE_DIR, item)
            if os.path.isdir(path):
                has_torrent = os.path.exists(os.path.join(BASE_DIR, f"{item}.torrent"))
                has_img = os.path.exists(os.path.join(BASE_DIR, f"{item}_Stitched_4K.jpg"))
                status = "✅ 已完成" if (has_torrent and has_img) else "⏳ 待处理"
                folders.append({"name": item, "status": status, "ready": (has_torrent and has_img)})
    return {"folders": folders}

# 执行单一任务并注入环境参数
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

# 云端无感热更新接口
@app.post("/api/update")
def update_system():
    try:
        script_url = "https://raw.githubusercontent.com/taizi8888/argOSBX/main/pt-webui/pt_make_headless.sh"
        urllib.request.urlretrieve(script_url, "/app/pt_make_headless.sh")
        os.chmod("/app/pt_make_headless.sh", 0o755)
        subprocess.run(["dos2unix", "/app/pt_make_headless.sh"])
        return {"message": "✅ 核心逻辑热更新成功！无需重启容器。"}
    except Exception as e:
        return {"message": f"❌ 更新失败: {str(e)}"}

# 文件下载与预览接口
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
