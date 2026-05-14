#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="${VENV_DIR:-$ROOT_DIR/.venv}"
MODEL_PATH="${MODEL_PATH:-$ROOT_DIR/models/DeepSeek-R1-Distill-Qwen-7B}"
MODEL_ID="${MODEL_ID:-deepseek-ai/DeepSeek-R1-Distill-Qwen-7B}"
SERVED_MODEL_NAME="${SERVED_MODEL_NAME:-deepseek-r1-distill-qwen-7b}"

export UV_CACHE_DIR="${UV_CACHE_DIR:-$ROOT_DIR/.uv-cache}"
export VLLM_NO_USAGE_STATS="${VLLM_NO_USAGE_STATS:-1}"
export VLLM_USE_V1="${VLLM_USE_V1:-0}"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

ensure_venv() {
  if [[ ! -x "$VENV_DIR/bin/python" ]]; then
    need_cmd uv
    uv venv "$VENV_DIR" --python 3.11
  fi

  if ! "$VENV_DIR/bin/python" -c "import vllm, modelscope, safetensors" >/dev/null 2>&1; then
    need_cmd uv
    uv pip install --python "$VENV_DIR/bin/python" \
      vllm==0.8.5 \
      modelscope \
      transformers==4.51.3 \
      'tokenizers>=0.21,<0.22'
  fi
}

download_model() {
  mkdir -p "$MODEL_PATH"
  "$VENV_DIR/bin/modelscope" download \
    --model "$MODEL_ID" \
    --local_dir "$MODEL_PATH" \
    --include \
      config.json \
      generation_config.json \
      tokenizer.json \
      tokenizer_config.json \
      "*.safetensors" \
      "*.safetensors.index.json" \
    --max-workers "${MODELSCOPE_MAX_WORKERS:-4}"
}

validate_model() {
  "$VENV_DIR/bin/python" - "$MODEL_PATH" <<'PY'
import sys
from pathlib import Path
from safetensors import safe_open

model_dir = Path(sys.argv[1])
files = sorted(model_dir.glob("*.safetensors"))
if not files:
    raise SystemExit(f"No safetensors files found in {model_dir}")

with safe_open(str(files[0]), framework="pt") as f:
    keys = list(f.keys())
if not keys:
    raise SystemExit(f"No tensors found in {files[0]}")
print(f"Validated {model_dir}: {len(files)} safetensors file(s), first shard has {len(keys)} tensors")
PY
}

if [[ "${SKIP_SETUP:-0}" != "1" ]]; then
  ensure_venv
fi

if [[ "${SKIP_DOWNLOAD:-0}" != "1" ]]; then
  if ! compgen -G "$MODEL_PATH/*.safetensors" >/dev/null; then
    download_model
  fi
  validate_model
fi

exec "$VENV_DIR/bin/vllm" serve "$MODEL_PATH" \
  --host 0.0.0.0 \
  --port "${PORT:-8000}" \
  --served-model-name "$SERVED_MODEL_NAME" \
  --dtype half \
  --max-model-len "${MAX_MODEL_LEN:-4096}" \
  --gpu-memory-utilization "${GPU_MEMORY_UTILIZATION:-0.90}"

# curl http://127.0.0.1:8000/v1/chat/completions \
#   -H 'Content-Type: application/json' \
#   -d '{"model":"deepseek-r1-distill-qwen-7b","messages":[{"role":"user","content":"北京大学 vs 清华大学 计算机系"}],"max_tokens":1000}'
