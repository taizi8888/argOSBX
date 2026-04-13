from fastapi import FastAPI, BackgroundTasks
from fastapi.responses import FileResponse
import subprocess
import os

app = FastAPI()
BASE_DIR = os.getenv("BASE_DIR", "/downloads")

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

@app.post("/api/run/{mode}")
def run_task(mode: str, folder: str = "", background_tasks: BackgroundTasks = None):
    def execute_script():
        cmd = ["/bin/bash", "/app/pt_make_headless.sh", f"--{mode}"]
        if folder:
            cmd.append(folder)
        subprocess.run(cmd)
        
    background_tasks.add_task(execute_script)
    return {"message": "任务已在后台启动！"}