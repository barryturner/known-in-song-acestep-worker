#!/usr/bin/env bash
set -euo pipefail

WORKSPACE="${WORKSPACE:-/workspace}"
COMFY_DIR="${COMFY_DIR:-/opt/ComfyUI}"
MODEL_DIR="${MODEL_DIR:-/opt/acestep-models}"
OUTPUT_DIR="${OUTPUT_DIR:-${WORKSPACE}/outputs}"
LOG_DIR="${WORKSPACE}/logs"
COMFY_PORT="${COMFY_PORT:-${PORT:-8188}}"

mkdir -p "${OUTPUT_DIR}" "${LOG_DIR}"
exec > >(tee -a "${LOG_DIR}/start_acestep15xl_$(date +%Y%m%d_%H%M%S).log") 2>&1

echo "[start] image-model worker starting: $(date -Iseconds)"
echo "[start] model source: ${MODEL_DIR}"

install_model() {
  local category="$1"
  local filename="$2"
  local expected_size="$3"
  local source="${MODEL_DIR}/split_files/${category}/${filename}"
  local target_dir="${COMFY_DIR}/models/${category}"
  local actual_size

  test -f "${source}" || { echo "[start] missing baked model: ${source}"; exit 1; }
  actual_size="$(stat -c %s "${source}")"
  test "${actual_size}" = "${expected_size}" || {
    echo "[start] incorrect baked model size: ${source} (${actual_size})"; exit 1;
  }
  mkdir -p "${target_dir}"
  ln -sfn "${source}" "${target_dir}/${filename}"
  echo "[start] linked baked model: ${filename}"
}

install_model diffusion_models acestep_v1.5_xl_sft_bf16.safetensors 9974719930
install_model text_encoders qwen_0.6b_ace15.safetensors 1191588248
install_model text_encoders qwen_4b_ace15.safetensors 8379154232
install_model vae ace_1.5_vae.safetensors 337431732

COMFY_ARGS=(--listen 0.0.0.0 --port "${COMFY_PORT}" --output-directory "${OUTPUT_DIR}")
if [ -n "${COMFY_EXTRA_ARGS:-}" ]; then
  # shellcheck disable=SC2206
  COMFY_ARGS+=(${COMFY_EXTRA_ARGS})
fi

cd "${COMFY_DIR}"
python main.py "${COMFY_ARGS[@]}" &
COMFY_PID=$!

echo "[start] starting serverless handler"
if PYTHONPATH=/opt/runpod/pylibs python /opt/runpod/handler.py; then
  echo "[start] handler returned cleanly"
elif [ -n "${RUNPOD_ENDPOINT_ID:-}" ]; then
  echo "[start] serverless handler failed"
  exit 1
fi

wait "${COMFY_PID}"
