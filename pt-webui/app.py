@app.post("/api/update")
def update_system(background_tasks: BackgroundTasks):
    try:
        base_url = "https://raw.githubusercontent.com/taizi8888/argOSBX/main/pt-webui"
        
        # 1. 🌐 OTA 更新前端 UI (index.html)
        html_url = f"{base_url}/index.html"
        html_content = urllib.request.urlopen(html_url).read().decode('utf-8')
        with open("index.html", "w", encoding="utf-8") as f:
            f.write(html_content)

        # 2. ⚙️ OTA 更新底层算法 (pt_make_headless.sh)
        bash_url = f"{base_url}/pt_make_headless.sh"
        bash_content = urllib.request.urlopen(bash_url).read().decode('utf-8').replace('\r\n', '\n')
        with open("/app/pt_make_headless.sh", "w", encoding="utf-8", newline='\n') as f:
            f.write(bash_content)
        os.chmod("/app/pt_make_headless.sh", 0o755)

        # 3. 🧠 OTA 更新核心后端 (app.py)
        app_url = f"{base_url}/app.py"
        app_content = urllib.request.urlopen(app_url).read().decode('utf-8')
        with open("/app/app.py", "w", encoding="utf-8") as f:
            f.write(app_content)

        # 4. 💥 触发自杀式重启机制 (延迟2秒执行，确保能把成功消息先发给网页前端)
        def restart_server():
            import time
            time.sleep(2)
            os._exit(0) # 强制退出进程，Docker 守护进程会瞬间拉起新容器
            
        background_tasks.add_task(restart_server)

        return {"message": "✅ OTA 全量升级包已下载并覆盖！\n\n前端已更新，后端系统将在 2 秒后自动重启。请稍后刷新网页即可看到全新版本。"}
        
    except Exception as e:
        return {"message": f"❌ OTA 升级失败: {str(e)}\n请检查网络或 GitHub 文件路径。"}
