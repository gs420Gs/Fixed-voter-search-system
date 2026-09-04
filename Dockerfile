FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

RUN apt-get update \
    && apt-get install -y --no-install-recommends tesseract-ocr tesseract-ocr-ben \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY requirements.txt ./
RUN python -m pip install --upgrade pip \
    && pip install -r requirements.txt

COPY . .
# /app/data holds the SQLite DB + uploaded PDFs. On Render's free plan
# this resets on redeploy (no persistent disk on free); attach a paid
# disk mounted here if you need it to survive redeploys.
RUN mkdir -p /app/data/uploads

CMD ["sh", "-c", "exec uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-10000}"]
