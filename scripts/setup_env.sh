#!/usr/bin/env bash
# Recreate the environment used for this reproduction (as run on 2026-10-05).
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="${SOFTSKILL_ROOT:-/data/a84460786/softskill_qwen3}"
mkdir -p "${ROOT}"/{data,checkpoints,results/logs}
git -C "${REPO}" submodule update --init
# Apply our patches to the pinned upstream checkout (idempotent):
#   qwen3.patch                       opt-in gradient checkpointing (single-round + agentic)
#   spreadsheet_docker_sandbox.patch  opt-in Docker sandbox for SpreadsheetBench generated code
for patch in "${REPO}"/patches/*.patch; do
  if git -C "${REPO}/third_party/SoftSkill" apply --check "${patch}" 2>/dev/null; then
    git -C "${REPO}/third_party/SoftSkill" apply "${patch}"
  fi
done
[[ -x "${ROOT}/venv/bin/python" ]] || virtualenv "${ROOT}/venv"   # python3-venv/ensurepip is not installed on this host
P="${ROOT}/venv/bin/pip"
"$P" install torch==2.14.0 --index-url https://download.pytorch.org/whl/cu130
"$P" install transformers==5.17.0 accelerate peft datasets huggingface_hub pillow qwen-vl-utils pytest tqdm flash-linear-attention ninja packaging
# Fast Qwen3.5 linear-attention conv kernel (only matters for the Qwen3.5-4B sanity check).
CUDA_HOME=/usr/local/cuda TORCH_CUDA_ARCH_LIST=8.0 CAUSAL_CONV1D_FORCE_BUILD=TRUE "$P" install --no-build-isolation causal-conv1d
"$P" install -e "${REPO}/third_party/SoftSkill"
# Agentic tasks: ALFWorld (fast-downward's build calls a bare `python`, so the venv must be on PATH).
PATH="${ROOT}/venv/bin:${PATH}" "$P" install "alfworld>=0.4.0" "gymnasium>=0.29.0"
# Separate vLLM venv for rollouts / prompt-embeds serving (vLLM pins its own torch).
[[ -x "${ROOT}/venv_vllm/bin/python" ]] || virtualenv "${ROOT}/venv_vllm"
PATH="${ROOT}/venv_vllm/bin:${PATH}" "${ROOT}/venv_vllm/bin/pip" install vllm==0.31.0
"${ROOT}/venv_vllm/bin/pip" install --no-deps -e "${REPO}/third_party/SoftSkill"
# SpreadsheetBench code sandbox image (enable with SOFTSKILL_SHEET_SANDBOX_IMAGE=softskill-sheet-sandbox:1).
docker build -t softskill-sheet-sandbox:1 "${REPO}/docker/spreadsheet_sandbox"
