# Configs

No new YAML files: every run uses the **upstream Table-1 configs** from the pinned
submodule, and `scripts/run_one.sh` overrides only the model path and per-run settings
with `--cfg-options`.

| Task | Upstream config | Split dir (under `/data/a84460786/softskill_qwen3/data/`) |
|---|---|---|
| SearchQA | `third_party/SoftSkill/configs/searchqa/soft_prefix.yaml` | `searchqa_split` (400/200/1400) |
| LiveMath | `third_party/SoftSkill/configs/livemathematicianbench/soft_prefix.yaml` | `livemathematicianbench_split` (35/18/124) |

## Effective hyperparameters (from upstream YAML, unchanged)

| | SearchQA | LiveMath |
|---|---|---|
| prefix_length | 32 | 32 |
| init | text: `skillopt/envs/searchqa/skills/initial.md` (21 Qwen3 tokens, tiled to 32) | text: `skillopt/envs/livemathematicianbench/skills/initial.md` (202 tokens, first 32 used) |
| optimizer | AdamW, lr 1e-3, wd 0 | AdamW, lr 1e-3, wd 0 |
| batch size / accumulation | 8 / 1 | 8 / 1 |
| epochs | 3 (validate after every epoch) | 3 |
| selection | `gate_metric: soft` (token F1) on first 64 val items | `gate_metric: hard` (accuracy) on all 18 val items |
| target | `<answer>{first gold answer}</answer><|im_end|>` (no CoT) | `<answer>{label}</answer><|im_end|>` (no CoT) |
| max_prompt_tokens / max_target_tokens | 2048 / 64 | 2048 / 16 |
| decoding | greedy (temperature 0), max_new_tokens 64, non-thinking | greedy, max_new_tokens 16, non-thinking |
| inference backend | `local_hf` (the README/launcher default) | `local_hf` |
| dtype | bf16 (`torch_dtype: auto` on CUDA) | bf16 |

## Per-run overrides added by `scripts/run_one.sh`

* always: `soft_prefix.inference_backend=local_hf`, `soft_prefix.injection_position=<pos>`, `train.seed=<seed>`,
  `--model_name /data/models/huggingface/qwen3-8b`
* Qwen3-8B (and the Qwen3.5-4B sanity check): `soft_prefix.gradient_checkpointing=true` (new opt-in flag from
  `patches/qwen3.patch`; without it the upstream batch of 8 OOMs on a 40 GB A100)
* `init`: `train.num_epochs=0 soft_prefix.eval_init_prefix=true soft_prefix.eval_init_val=true`
* `noskill`: `train.num_epochs=0 soft_prefix.eval_plain_baseline=true`
* `hard`: as `noskill` plus `soft_prefix.max_prompt_tokens=8192`, run through `scripts/run_with_hard_skill.py`, which
  renders `ckpt/<task>/gpt5.5_skill.md` into the system-prompt skill section
