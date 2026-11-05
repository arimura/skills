# skills

General-purpose Claude Code skills that I use across projects.

## Skills

| Skill | What it does |
|---|---|
| [copilot-review-loop](skills/copilot-review-loop/SKILL.md) | Opens a PR, or reuses an open one. Then repeats GitHub Copilot code review rounds until the feedback converges or a round cap is reached. Works with `gh` or the GitHub MCP tools. |

## Install

### claude.ai (also works in Claude Code cloud sessions)

claude.ai takes **one ZIP per skill**, with the skill folder at the root of the ZIP. Build the ZIPs with:

```bash
make
```

This writes `dist/<skill-name>.zip` for every skill under `skills/`. To package one skill, run `make dist/<skill-name>.zip`. A skill gets no ZIP if its `name` differs from the folder name, or if its `description` is empty or longer than 200 characters.

Then upload each ZIP from the Skills section of claude.ai's settings. Uploaded skills sync to Claude Code sessions signed in with the same account, including cloud sessions. To update a skill, run `make` again and re-upload its ZIP.

### Local Claude Code

Symlink a skill into your personal skills directory:

```bash
mkdir -p ~/.claude/skills && ln -s "$(pwd)/skills/copilot-review-loop" ~/.claude/skills/copilot-review-loop
```

## Adding a skill

1. Create `skills/<skill-name>/SKILL.md`. Its frontmatter `name` must equal `<skill-name>`.
2. Run `make dist/<skill-name>.zip` to check the limits above.
