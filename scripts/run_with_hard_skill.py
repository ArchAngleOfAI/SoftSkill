#!/usr/bin/env python3
"""Hard-skill (text) baseline inside the upstream soft-prefix harness.

Runs the upstream entry point `scripts/train_soft_prefix.py` unchanged with
`train.num_epochs=0 soft_prefix.eval_plain_baseline=true` (plain model, no
prefix), but first swaps the prompt builders used by the upstream evaluators so
that the SkillOpt Markdown artifact (path in $HARD_SKILL_PATH) is rendered into
the system prompt's skill section exactly as the upstream SkillOpt rollout does
(`_build_system(skill_content)` -> "## Skill\n<skill>\n\n"). Decoding, scoring,
splits and output layout are therefore identical to the no-skill / SoftSkill
runs. Only SearchQA and LiveMath are supported.
"""
from __future__ import annotations

import os
import runpy
import sys

UPSTREAM = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "third_party", "SoftSkill")
sys.path.insert(0, UPSTREAM)

import skillopt.softprefix.trainer as trainer  # noqa: E402
from skillopt.envs.livemathematicianbench.rollout import _build_system as livemath_system  # noqa: E402
from skillopt.envs.livemathematicianbench.rollout import _build_user as livemath_user  # noqa: E402
from skillopt.envs.searchqa.rollout import _build_system as searchqa_system  # noqa: E402
from skillopt.envs.searchqa.rollout import _build_user as searchqa_user  # noqa: E402
from skillopt.softprefix.data import _apply_text_chat_template  # noqa: E402

with open(os.environ["HARD_SKILL_PATH"], encoding="utf-8") as f:
    SKILL = f.read()
print(f"[hard-skill] using {os.environ['HARD_SKILL_PATH']} ({len(SKILL)} chars)", flush=True)


def build_searchqa_prompt(tokenizer, item, *, enable_thinking=False):
    messages = [
        {"role": "system", "content": searchqa_system(SKILL)},
        {"role": "user", "content": searchqa_user(question=str(item["question"]), context=str(item.get("context", "")))},
    ]
    return _apply_text_chat_template(tokenizer, messages, enable_thinking=enable_thinking)


def build_searchqa_prompt_and_insert_idx(tokenizer, item, *, enable_thinking=False, injection_position="prompt_start"):
    return build_searchqa_prompt(tokenizer, item, enable_thinking=enable_thinking), None


def build_livemath_prompt_and_insert_idx(
    tokenizer, item, *, use_theorem=False, use_sketch=False, enable_thinking=False, injection_position="prompt_start"
):
    messages = [
        {"role": "system", "content": livemath_system(SKILL)},
        {"role": "user", "content": livemath_user(item, use_theorem=use_theorem, use_sketch=use_sketch)},
    ]
    return _apply_text_chat_template(tokenizer, messages, enable_thinking=enable_thinking), None


trainer.build_searchqa_prompt = build_searchqa_prompt
trainer.build_searchqa_prompt_and_insert_idx = build_searchqa_prompt_and_insert_idx
trainer.build_livemath_prompt_and_insert_idx = build_livemath_prompt_and_insert_idx

if "train.num_epochs=0" not in sys.argv or "soft_prefix.eval_plain_baseline=true" not in sys.argv:
    raise SystemExit("run_with_hard_skill.py is eval-only: pass train.num_epochs=0 soft_prefix.eval_plain_baseline=true")

sys.argv[0] = os.path.join(UPSTREAM, "scripts", "train_soft_prefix.py")
runpy.run_path(sys.argv[0], run_name="__main__")
