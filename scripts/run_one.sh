#!/usr/bin/env bash
# Run one SoftSkill configuration through the UPSTREAM entry point
# (third_party/SoftSkill/scripts/train_soft_prefix.py) with the upstream
# Table-1 YAML config; only the model and per-run settings are overridden.
#
# usage: run_one.sh TASK POSITION SEED MODE MODEL_TAG GPU [extra cfg-options...]
#   TASK      searchqa | livemath
#   POSITION  prompt_start | skill_section
#   MODE      train   - SoftSkill: p0 from NL skill, train delta, select by val
#             init    - init-only: p0 inserted, no training (num_epochs=0)
#             init_maxpool / init_meanpool - init-only with p0 = element-wise max / mean of the NL
#                       skill's token embeddings, tiled to the prefix length (patches/pooled_init.patch)
#             noskill - plain model, no prefix, no skill text
#             hard    - SkillOpt Markdown artifact as text in the skill section
#   MODEL_TAG qwen3_8b | qwen35_4b
# env RUN_TAG (optional): run-name suffix for non-upstream variants, e.g. RUN_TAG=gen2048
#   together with soft_prefix.max_new_tokens=2048 (summarize.py reads gen<N> as the budget).
set -euo pipefail

TASK=$1; POS=$2; SEED=$3; MODE=$4; MODEL_TAG=$5; GPU=$6; shift 6
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UP="${REPO}/third_party/SoftSkill"
ROOT="${SOFTSKILL_ROOT:-/data/a84460786/softskill_qwen3}"
PY="${ROOT}/venv/bin/python"

case "${MODEL_TAG}" in
  qwen3_8b)  MODEL=/data/models/huggingface/qwen3-8b ;;
  qwen35_4b) MODEL=/data/models/library/Qwen3.5-4B ;;
  *) echo "unknown model tag ${MODEL_TAG}" >&2; exit 1 ;;
esac
case "${TASK}" in
  searchqa) CONFIG=configs/searchqa/soft_prefix.yaml; SPLIT="${ROOT}/data/searchqa_split"; SKILL_DIR=searchqa ;;
  livemath) CONFIG=configs/livemathematicianbench/soft_prefix.yaml; SPLIT="${ROOT}/data/livemathematicianbench_split"; SKILL_DIR=livemath ;;
  *) echo "unknown task ${TASK}" >&2; exit 1 ;;
esac

RUN="${MODEL_TAG}_${TASK}_${MODE}_${POS}_seed${SEED}${RUN_TAG:+_${RUN_TAG}}"
OUT="${ROOT}/results/runs/${RUN}"
LOG="${ROOT}/results/logs/${RUN}.log"
mkdir -p "${ROOT}/results/runs" "${ROOT}/results/logs" "${ROOT}/checkpoints" "${ROOT}/tmp"
# Keep temp files on /data: the shared root filesystem (/tmp) filled up and crashed runs.
export TMPDIR="${ROOT}/tmp"
if [[ -f "${OUT}/summary.json" ]]; then echo "skip ${RUN} (summary exists)"; exit 0; fi

opts=(
  soft_prefix.inference_backend=local_hf
  soft_prefix.injection_position="${POS}"
  train.seed="${SEED}"
)
ENTRY=(scripts/train_soft_prefix.py)
case "${MODE}" in
  train) ;;
  init)    opts+=(train.num_epochs=0 soft_prefix.eval_init_prefix=true soft_prefix.eval_init_val=true) ;;
  init_maxpool)  opts+=(train.num_epochs=0 soft_prefix.eval_init_prefix=true soft_prefix.eval_init_val=true soft_prefix.init_strategy=text_max_pool) ;;
  init_meanpool) opts+=(train.num_epochs=0 soft_prefix.eval_init_prefix=true soft_prefix.eval_init_val=true soft_prefix.init_strategy=text_mean_pool) ;;
  noskill) opts+=(train.num_epochs=0 soft_prefix.eval_plain_baseline=true) ;;
  hard)
    # Same harness as noskill, but the prompt builders render the SkillOpt
    # artifact into the skill section (adapter: scripts/run_with_hard_skill.py).
    # max_prompt_tokens is raised so the long Markdown skill never truncates
    # the question/context away (upstream truncates on the right at 2048).
    opts+=(train.num_epochs=0 soft_prefix.eval_plain_baseline=true soft_prefix.max_prompt_tokens=8192)
    export HARD_SKILL_PATH="${ROOT}/data/skills/${SKILL_DIR}/skillopt_gpt5.5_skill.md"
    ENTRY=("${REPO}/scripts/run_with_hard_skill.py")
    ;;
  *) echo "unknown mode ${MODE}" >&2; exit 1 ;;
esac
opts+=("$@")

cd "${UP}"
{
  echo "# run=${RUN} host=$(hostname) gpu=${GPU} start=$(date -Is)"
  echo "# upstream_commit=$(git -C "${UP}" rev-parse HEAD) patch_applied=$(git -C "${UP}" diff --quiet && echo no || echo yes)"
  echo "# model=${MODEL} config=${CONFIG} split=${SPLIT}"
  echo "# cfg-options: ${opts[*]}"
} > "${LOG}"
export PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True HF_HOME="${ROOT}/data/hf_cache" TOKENIZERS_PARALLELISM=false
START=$(date +%s)
CUDA_VISIBLE_DEVICES="${GPU}" "${PY}" "${ENTRY[@]}" \
  --config "${CONFIG}" --split_dir "${SPLIT}" --model_name "${MODEL}" \
  --cfg-options "${opts[@]}" --out_root "${OUT}" >> "${LOG}" 2>&1
echo "# end=$(date -Is) wall_s=$(( $(date +%s) - START ))" >> "${LOG}"

# Large artifacts -> checkpoints/, leave symlinks in the run dir.
shopt -s nullglob
pts=("${OUT}"/*.pt)
if (( ${#pts[@]} )); then
  mkdir -p "${ROOT}/checkpoints/${RUN}"
  for f in "${pts[@]}"; do mv "$f" "${ROOT}/checkpoints/${RUN}/" && ln -s "${ROOT}/checkpoints/${RUN}/$(basename "$f")" "$f"; done
fi
