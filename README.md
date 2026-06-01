# claude-sandbox

Run Claude Code inside a sandboxed devcontainer so prompt injection from
scraped data, fetched web pages, or tool results cannot reach your secrets,
cluster, or git remote.

## Security model

The container has no access to:
- `~/.kube`, `~/.aws`, `~/.ssh`, cloud credentials — remote ops fail physically
D- The main repo root — Claude cannot modify `.devcontainer/` or this script

Local git commits work normally. `git push` fails: no credentials are mounted.
All pushes are done manually from the host after reviewing the diff.

The sandbox config (`.devcontainer/devcontainer.json`) is always read from
the main repo root via `--config`, never from inside the container.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/tailosoft/claude-sandbox/main/claude-sandbox.sh \
  | sudo tee /usr/local/bin/claude-sandbox > /dev/null \
  && sudo chmod +x /usr/local/bin/claude-sandbox
```

Then enable tab completion (once):

```bash
claude-sandbox --install-completion
```

## Usage

```
claude-sandbox <branch> [prompt]
claude-sandbox --cleanup
claude-sandbox --install-completion
claude-sandbox -h | --help
```

### Examples

```bash
claude-sandbox feat/login
claude-sandbox feat/login implement the password reset flow
claude-sandbox main review the codebase and give honest feedback
claude-sandbox --cleanup
```

## Requirements

- [Docker](https://docs.docker.com/get-docker/)
- [`@devcontainers/cli`](https://github.com/devcontainers/cli): `npm install -g @devcontainers/cli`
- Your repo must have a `.devcontainer/devcontainer.json`

## Devcontainer setup

Your repo's `.devcontainer/devcontainer.json` controls what is and isn't
mounted. The recommended setup mounts only what Claude Code needs to
authenticate and load your preferences:

```jsonc
{
  "mounts": [
    // Claude Code auth and preferences (selective — no history or project memory)
    "source=${localEnv:HOME}/.claude.json,target=/home/vscode/.claude.json,type=bind",
    "source=${localEnv:HOME}/.claude/.credentials.json,target=/home/vscode/.claude/.credentials.json,type=bind",
    "source=${localEnv:HOME}/.claude/settings.json,target=/home/vscode/.claude/settings.json,type=bind",
    "source=${localEnv:HOME}/.claude/stats-cache.json,target=/home/vscode/.claude/stats-cache.json,type=bind",
    "source=${localEnv:HOME}/.claude/skills,target=/home/vscode/.claude/skills,type=bind,readonly",
    "source=${localEnv:HOME}/.claude/plugins,target=/home/vscode/.claude/plugins,type=bind,readonly"
  ],
  "runArgs": ["--cap-drop=ALL", "--security-opt=no-new-privileges"]
}
```

### Hiding secrets inside the workspace

If your repo stores secrets inside the project directory (`.env`, `secrets/`,
etc.) you can shadow them with a tmpfs so they appear empty inside the container
while remaining untouched on the host:

```jsonc
"mounts": [
  // shadow a file — appears as an empty file inside the container
  "source=/dev/null,target=/workspace/.env,type=bind,readonly",

  // shadow a directory — appears as an empty directory inside the container
  "target=/workspace/secrets,type=tmpfs"
]
```

The host files are never modified. Shadowing works for any path inside
`/workspace` — add one entry per file or folder you want to hide.

See the `registry-scraper` reference implementation for a full working example
including a Java/Node Dockerfile.

## Handoff file

`.claude/handoff.md` (gitignored) is a shared scratchpad between you and Claude:

- **Before a session** — write your instructions there on the host
- **After a session** — ask Claude to summarise what it did; pick up on the host

The default prompt reads this file automatically if no prompt argument is given.