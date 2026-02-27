FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY pyproject.toml langgraph.json README.md ./
COPY src/ ./src/

RUN pip install --no-cache-dir -e .

ENV LANGGRAPH_DATA_DIR=/app/data
ENV PORT=8123

RUN mkdir -p /app/data

HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
    CMD curl -f http://localhost:8123/info || exit 1

EXPOSE 8123

CMD ["langgraph", "dev", "--host", "0.0.0.0", "--port", "8123"]
