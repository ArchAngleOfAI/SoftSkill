#!/usr/bin/env bash
# Qwen3-8B LiveMath at max_new_tokens=2048, seeds 1-3, served by the soft-prefix vLLM
# server on one GPU: init-only windowed mean-pooled p0 (POOL_WINDOW / POOL_STRIDE,
# defaults 8 / 6) at prompt_start and skill_section, plus the no-skill baseline.
# usage: launch_livemath_winpool.sh [GPU] [PORT]
set -uo pipefail
GPU=${1:-2}; PORT=${2:-8110}
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="${SOFTSKILL_ROOT:-/data/a84460786/softskill_qwen3}"
MODEL=/data/models/huggingface/qwen3-8b
SERVER_LOG="${ROOT}/results/logs/vllm_server_qwen3_8b_gpu${GPU}_winpool.log"
export TMPDIR="${ROOT}/tmp" HF_HOME="${ROOT}/data/hf_cache"

echo "$(date -Is) starting vLLM server on GPU ${GPU}:${PORT}"
(cd "${REPO}/third_party/SoftSkill" && CUDA_VISIBLE_DEVICES="${GPU}" exec setsid "${ROOT}/venv_vllm/bin/python" -m skillopt.softprefix.vllm_prompt_embeds \
  --model_name "${MODEL}" --port "${PORT}" --gpu-memory-utilization 0.88 --max-model-len 16384) > "${SERVER_LOG}" 2>&1 &
SERVER=$!
trap 'kill -- -${SERVER} 2>/dev/null; wait ${SERVER} 2>/dev/null' EXIT
until grep -q "service listening" "${SERVER_LOG}"; do
  kill -0 ${SERVER} 2>/dev/null || { echo "server died, see ${SERVER_LOG}"; exit 1; }
  sleep 10
done
echo "$(date -Is) server up"

opts=(soft_prefix.max_new_tokens=2048 soft_prefix.inference_backend=vllm_prompt_embeds
  soft_prefix.inference_base_url="http://127.0.0.1:${PORT}" soft_prefix.device=cpu
  soft_prefix.torch_dtype=bfloat16 soft_prefix.inference_timeout_seconds=3600)
for SEED in 1 2 3; do
  for spec in "prompt_start init_winpool" "skill_section init_winpool" "prompt_start noskill"; do
    read -r POS MODE <<< "${spec}"
    echo "$(date -Is) run livemath ${MODE} ${POS} seed${SEED}"
    RUN_TAG=gen2048 "${REPO}/scripts/run_one.sh" livemath "${POS}" "${SEED}" "${MODE}" qwen3_8b "${GPU}" "${opts[@]}" \
      || echo "$(date -Is) FAILED livemath ${MODE} ${POS} seed${SEED}"
  done
done
"${ROOT}/venv/bin/python" "${REPO}/scripts/summarize.py" && echo "$(date -Is) summary written"
echo "$(date -Is) ALL DONE"
