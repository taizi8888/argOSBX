FROM python:3.11-slim-bullseye

RUN apt-get update && apt-get install -y \
    mediainfo \
    mktorrent \
    ffmpeg \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY pt_make_headless.sh .
RUN chmod +x pt_make_headless.sh

COPY app.py .
COPY index.html .

EXPOSE 8080
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8080"]