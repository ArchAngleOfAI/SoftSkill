#!/usr/bin/env bash
# Queue all Qwen3-8B Table-1 runs over the given GPUs (one worker per GPU).
# usage: nohup scripts/launch_all.sh "5 6" > /data/.../results/logs/launch_all.out 2>&1 &
set -uo pipefail
GPUS=(${1:-5 6})
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="${SOFTSKILL_ROOT:-/data/a84460786/softskill_qwen3}"
QUEUE="${ROOT}/results/logs/queue.txt"
GC=soft_prefix.gradient_checkpointing=true   # required to fit Qwen3-8B on 40 GB (see patches/qwen3.patch)

if [[ ! -f "${QUEUE}" ]]; then
  {
    # Main SoftSkill runs: 2 tasks x 2 placements x 3 seeds
    for task in searchqa livemath; do for pos in prompt_start skill_section; do for seed in 1 2 3; do
      echo "${task} ${pos} ${seed} train"; done; done; done
    # Baselines. SearchQA eval is seed-independent (fixed items, greedy), so one
    # seed (+ a seed-2 no-skill determinism check); LiveMath shuffles answer
    # choices per seed, so all three seeds.
    echo "searchqa prompt_start 1 noskill"; echo "searchqa prompt_start 2 noskill"
    echo "searchqa skill_section 1 hard"
    echo "searchqa prompt_start 1 init"; echo "searchqa skill_section 1 init"
    for seed in 1 2 3; do
      echo "livemath prompt_start ${seed} noskill"; echo "livemath skill_section ${seed} hard"
      echo "livemath prompt_start ${seed} init"; echo "livemath skill_section ${seed} init"
    done
  } > "${QUEUE}"
fi

worker() {
  local gpu=$1 line
  while true; do
    line=$(flock "${QUEUE}.lock" bash -c "head -n1 '${QUEUE}'; sed -i '1d' '${QUEUE}'")
    [[ -z "${line}" ]] && break
    read -r task pos seed mode <<< "${line}"
    echo "$(date -Is) gpu=${gpu} START ${line}"
    "${REPO}/scripts/run_one.sh" "${task}" "${pos}" "${seed}" "${mode}" qwen3_8b "${gpu}" "${GC}"
    local rc=$?   # capture before $(date) resets $?
    echo "$(date -Is) gpu=${gpu} END   ${line} rc=${rc}"
    "${REPO}/scripts/mirror_logs.sh" > /dev/null 2>&1 || true
  done
}
for g in "${GPUS[@]}"; do worker "${g}" & done
wait
"${REPO}/scripts/mirror_logs.sh"
echo "$(date -Is) ALL DONE"
