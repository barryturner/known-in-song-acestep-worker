ARG BASE_IMAGE=runpod/pytorch:1.0.2-cu1281-torch280-ubuntu2404
FROM ${BASE_IMAGE}

ARG COMFYUI_REPO=https://github.com/Comfy-Org/ComfyUI.git
ARG COMFYUI_REF=v0.32.0
ARG MODEL_REPO=Comfy-Org/ace_step_1.5_ComfyUI_files
ARG MODEL_REVISION=6707deb277e9e0907fd9c14ce6b6f1d695c6a3fc

LABEL org.opencontainers.image.source="https://github.com/barryturner/known-in-song-acestep-worker"
LABEL org.opencontainers.image.description="Minimal queue worker for ACE-Step 1.5 XL SFT with four pinned model assets"

ENV DEBIAN_FRONTEND=noninteractive \
    COMFY_DIR=/opt/ComfyUI \
    MODEL_DIR=/opt/acestep-models \
    HF_XET_HIGH_PERFORMANCE=1 \
    PIP_NO_CACHE_DIR=1 \
    PYTHONUNBUFFERED=1

# Queue-only worker: omit SSH, Jupyter, and the Pod UI extras from the previous
# community image. The Runpod base supplies the compatible CUDA/Torch runtime
# and is commonly cached on Runpod hosts.
RUN apt-get update && apt-get install -y --no-install-recommends \
      git ca-certificates ffmpeg libgl1 libglib2.0-0 libsndfile1 \
    && rm -rf /var/lib/apt/lists/*

# Pin the base Torch family while installing ComfyUI so pip cannot silently
# replace it with an incompatible build.
RUN set -eux; \
    python -m pip install --upgrade pip; \
    python -m pip freeze | grep -E '^(torch|torchvision|torchaudio)==' > /opt/torch-constraints.txt; \
    test -s /opt/torch-constraints.txt; \
    git clone --depth 1 --branch "${COMFYUI_REF}" "${COMFYUI_REPO}" "${COMFY_DIR}"; \
    python -m pip install huggingface_hub; \
    python -m pip install -r "${COMFY_DIR}/requirements.txt" -c /opt/torch-constraints.txt; \
    python -m pip install --target /opt/runpod/pylibs runpod; \
    PYTHONPATH=/opt/runpod/pylibs python -c 'import runpod; print(runpod.__version__)'; \
    python -c 'import torch, torchvision; print(torch.__version__, torchvision.__version__)'; \
    rm -rf /root/.cache/pip "${COMFY_DIR}/.git"

COPY model-sha256s.txt /tmp/model-sha256s.txt

# Download only the assets used by the accepted XL SFT workflow. The source
# revision and each large-file SHA-256 are fixed, then build-only metadata is
# removed so the runtime layer contains just the four files.
RUN set -eux; \
    hf download "${MODEL_REPO}" --revision "${MODEL_REVISION}" \
      --include split_files/diffusion_models/acestep_v1.5_xl_sft_bf16.safetensors \
      --include split_files/text_encoders/qwen_0.6b_ace15.safetensors \
      --include split_files/text_encoders/qwen_4b_ace15.safetensors \
      --include split_files/vae/ace_1.5_vae.safetensors \
      --local-dir "${MODEL_DIR}"; \
    cd "${MODEL_DIR}"; \
    sha256sum -c /tmp/model-sha256s.txt; \
    rm -rf .cache /tmp/model-sha256s.txt

COPY start.sh /opt/runpod/start.sh
COPY handler.py /opt/runpod/handler.py
RUN chmod +x /opt/runpod/start.sh

WORKDIR /workspace
CMD ["/opt/runpod/start.sh"]
