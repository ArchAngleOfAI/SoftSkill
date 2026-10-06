# Agent memory — short-term status (resume from here)

Last updated: 2026-10-06 ~20:35 UTC. Project: SoftSkill (arXiv 2606.20333) reproduction on Qwen3-8B.
Full write-up: `softskill_qwen3_report.md` (§1–7 first batch, §8 follow-up work).

## Layout
- Repo: `/home/a84460786/SoftSkills/softskill-qwen3` (local git, no remote; `gh` not installed).
- Upstream code: `third_party/SoftSkill` submodule @ 4fc5300, patched in place by `scripts/setup_env.sh`.
- Large files (not in git): `/data/a84460786/softskill_qwen3/{data,checkpoints,results,venv,venv_vllm,tmp}`.
- Run outputs: `/data/.../results/runs/<run>/summary.json`; logs `/data/.../results/logs/`.
- `scripts/mirror_logs.sh` copies logs into `logs/` and regenerates `logs/summary.{json,md}`.
- Python: `/data/a84460786/softskill_qwen3/venv/bin/python` (vLLM server uses `venv_vllm`).

## In flight right now
- Nothing running. Last job (`scripts/launch_livemath_hard_gen2048.sh 4 8111 2 3`) finished 20:31 UTC
  and released GPU 4 cleanly (setsid fix works). `logs/` mirrored at 20:32.
- Still occupied: orphaned vLLM engine of ours on GPU 2 (PID 1459446, ~39 GB) from the first
  `launch_livemath_winpool.sh` run. The agent was not allowed to kill it; the user needs to
  (`kill 1459446`).

## Latest results: Qwen3-8B LiveMath @ max_new_tokens=2048 (all seeds complete)
Test accuracy %, strict; lenient `\boxed{}` in parentheses. 124 test items, ~±4 pt sampling noise.

| Condition | s1 | s2 | s3 | mean ± std |
|---|---|---|---|---|
| No skill | 18.5 (26.6) | 21.8 (27.4) | 19.4 (25.8) | 19.9 ± 1.7 (26.6) |
| Hard skill (SkillOpt text) | 25.0 (32.3) | 25.8 (35.5) | 27.4 (35.5) | 26.1 ± 1.2 (34.4) |
| Windowed mean-pool p0 (w8 s6), init-only, prompt_start | 15.3 | 19.4 | 19.4 | 18.0 ± 2.3 |
| Windowed mean-pool p0 (w8 s6), init-only, skill_section | 16.9 (21.8) | 27.4 (30.6) | 26.6 (32.3) | 23.7 ± 5.8 (28.2) |

Takeaways: hard skill > no skill on every seed (+6.2). Untrained p0 gives no reliable gain over no
skill: prompt_start slightly worse on every seed (answers in ~57 tokens, skips reasoning);
skill_section +3.8 on average but noisy. Trained SoftSkill NOT yet evaluated at 2048 tokens
(38.2 at the upstream 16 tokens).

## Next steps
1. (done) All seeds complete; report §8.4 and this file updated.
2. Kill the orphaned GPU-2 engine (user).
3. (done) Everything committed, incl. `patches/window_pooled_init.patch` (all 4 patches verified to
   apply in setup_env.sh order and reproduce the submodule exactly). vLLM server logs not committed.
4. Suggested next experiment: trained SoftSkill checkpoints at max_new_tokens=2048.

## Gotchas
- Shared `/` filesystem fills up: always keep TMPDIR under /data (run_one.sh does this).
- GPU 0 avoided; other users' jobs share GPUs 0–7 — check `nvidia-smi` before launching.
- Hard-skill runs: injection_position=prompt_start is passed with an empty prefix (prompt has no
  skill_section marker); run name still says `skill_section`.
- `run_one.sh` skips runs whose `summary.json` already exists.
