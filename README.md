# Known in Song ACE-Step cold-start worker

An experimental, queue-only Runpod Serverless image for ACE-Step 1.5 XL SFT.
It is deliberately isolated from the Known in Song application.

The image starts from Runpod's pinned PyTorch/CUDA base and contains exactly
the four model files used by the accepted workflow. Files come from the public
Apache-2.0 `Comfy-Org/ace_step_1.5_ComfyUI_files` repository at revision
`6707deb277e9e0907fd9c14ce6b6f1d695c6a3fc`; their LFS SHA-256 values are
verified during the build. The worker source derives from the MIT-licensed
`RyoheiTanaka/runpod-template-acestep15xl` v0.4.4 implementation.

This image is an R&D artifact. It must not be treated as production-ready until
fresh-host startup, output compatibility, security, and repeated generation are
verified.
