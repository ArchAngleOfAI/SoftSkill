#!/usr/bin/env bash
# Materialize SearchQA and LiveMath official splits + skill artifacts under ${ROOT}/data.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UP="${REPO}/third_party/SoftSkill"
ROOT="${SOFTSKILL_ROOT:-/data/a84460786/softskill_qwen3}"
PY="${ROOT}/venv/bin/python"
export HF_HOME="${ROOT}/data/hf_cache"
cd "${ROOT}"
mkdir -p data
ln -sfn "${UP}/data/searchqa_id_split" data/searchqa_id_split
ln -sfn "${UP}/data/livemathematicianbench_id_split" data/livemathematicianbench_id_split
# SearchQA: upstream script, unchanged (resolves the released ID manifest against lucadiliello/searchqa).
"${PY}" "${UP}/scripts/data/prepare_searchqa.py"
# LiveMath: upstream prepare_livemath.py re-splits *all* months currently on HF (121/61/426 as of
# 2026-10-05), which is not the paper split; use the pinned-revision adapter instead (35/18/124).
"${PY}" "${REPO}/scripts/prepare_livemath_pinned.py" \
  --manifest_dir data/livemathematicianbench_id_split \
  --raw_dir data/livemathematicianbench/raw \
  --out_split_dir data/livemathematicianbench_split
# Skill artifacts (natural-language init skills and SkillOpt GPT-5.5 Markdown artifacts ship with upstream).
for t in searchqa:searchqa livemath:livemathematicianbench; do
  short=${t%%:*}; env=${t##*:}
  mkdir -p "data/skills/${short}"
  cp "${UP}/skillopt/envs/${env}/skills/initial.md" "data/skills/${short}/natural_language_initial.md"
  cp "${UP}/ckpt/${short}/gpt5.5_skill.md" "data/skills/${short}/skillopt_gpt5.5_skill.md"
done
