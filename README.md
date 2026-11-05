# skills

General-purpose Claude Code skills that I use across projects.

## Skills

| Skill | What it does |
|---|---|
| [copilot-review-loop](skills/copilot-review-loop/SKILL.md) | Opens a PR, or reuses an open one. Then repeats GitHub Copilot code review rounds until the feedback converges or a round cap is reached. Works with `gh` or the GitHub MCP tools. |

## Install

Symlink a skill into your personal skills directory:

```bash
ln -s "$(pwd)/skills/copilot-review-loop" ~/.claude/skills/copilot-review-loop
```
