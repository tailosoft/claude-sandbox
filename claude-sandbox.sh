#!/bin/bash
# Usage: ./claude-sandbox.sh <branch-name> [prompt]
#        ./claude-sandbox.sh --cleanup
#        ./claude-sandbox.sh --install-completion
#
# Creates a worktree for the branch (if needed), starts the devcontainer,
# and drops you into an interactive Claude session.
# If no prompt is given, Claude picks up from .claude/handoff.md.
SCRIPT="$(realpath "$0")"

if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  # Being sourced — register completion only
  _claude_sandbox() {
    if [ "$COMP_CWORD" -eq 1 ]; then
      local cur="${COMP_WORDS[1]}"
      # bail silently if not inside a git repo
      git rev-parse --git-dir &>/dev/null || return 0
      local candidates
      candidates=$(
        { git worktree list --porcelain 2>/dev/null \
            | awk '/^branch /{sub("refs/heads/",""); print $2}'
          git branch --format='%(refname:short)' 2>/dev/null
        } | awk '!seen[$0]++'
      )
      [ -n "$candidates" ] && COMPREPLY=($(compgen -W "$candidates" -- "$cur"))
    fi
  }
  complete -F _claude_sandbox claude-sandbox.sh ./claude-sandbox.sh claude-sandbox
  return
fi

set -eo pipefail
trap 'exit 130' INT
trap 'echo "Script failed — dropping into shell"; exec $SHELL' ERR

if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
  cat <<'EOF'
USAGE
  ./claude-sandbox.sh <branch> [prompt]
  ./claude-sandbox.sh --cleanup
  ./claude-sandbox.sh --install-completion
  ./claude-sandbox.sh -h | --help

DESCRIPTION
  Runs Claude Code inside a sandboxed devcontainer for a given git branch.
  Claude starts in auto mode (--dangerously-skip-permissions) — safe because
  the container has no access to kubectl, SSH keys, cloud credentials or secrets.

  The sandbox definition is always read from the main repo root (.devcontainer/)
  and is never mounted inside the container, so Claude cannot tamper with it.

ARGUMENTS
  <branch>   Git branch to work on. If a worktree already exists for it
             (anywhere on disk, e.g. import-jdl), it is reused. Otherwise
             a new worktree is created at .claude/worktrees/<branch>.

  [prompt]   Optional starting prompt passed directly to Claude.
             Words do not need to be quoted — everything after the branch
             name is joined into one prompt.
             Default: "read .claude/handoff.md and continue from there"

COMMANDS
  --cleanup               Remove Docker containers whose workspace folder no
                          longer exists on disk (i.e. the worktree was deleted).

  --install-completion    Append a source line to ~/.bashrc and ~/.zshrc so
                          that tab-completion on the first argument (branch name)
                          works permanently without manual sourcing.

  -h, --help              Show this help.

HANDOFF FILE
  .claude/handoff.md is a gitignored scratchpad shared between host and container.
  Write instructions before a session; ask Claude to summarise after.

EXAMPLES
  ./claude-sandbox.sh feat/login
  ./claude-sandbox.sh feat/login implement the password reset flow
  ./claude-sandbox.sh import-jdl review the JDL and suggest improvements
  ./claude-sandbox.sh --cleanup
  ./claude-sandbox.sh --install-completion

FIRST-TIME SETUP
  npm install -g @devcontainers/cli   # install the devcontainer CLI once
EOF
  exit 0
fi

if [ "$1" = "--cleanup" ]; then
  echo "Removing containers whose workspace folder no longer exists on disk..."
  docker ps -a --filter "label=devcontainer.local_folder" \
    --format "{{.ID}}\t{{.Label \"devcontainer.local_folder\"}}" \
  | while IFS=$'\t' read -r id folder; do
    if [ ! -d "$folder" ]; then
      echo "  removing $id ($folder)"
      docker rm -f "$id"
    fi
  done
  echo "Done."
  exit 0
fi

if [ "$1" = "--install-completion" ]; then
  LINE="source $SCRIPT"
  for RC in "$HOME/.bashrc" "$HOME/.zshrc"; do
    if [ -f "$RC" ] && ! grep -qF "$LINE" "$RC"; then
      echo "$LINE" >> "$RC"
      echo "Installed completion in $RC"
    fi
  done
  echo "Restart your shell or run: source $SCRIPT"
  exit 0
fi

BRANCH="${1:?Usage: $0 <branch-name> [prompt]}"
PROMPT="${*:2}"
PROMPT="${PROMPT:-read .claude/handoff.md and continue from there}"
ROOT="$(git rev-parse --show-toplevel)"

# Reuse existing worktree regardless of where it lives (e.g. import-jdl)
WORKTREE=$(git worktree list --porcelain \
  | awk -v b="refs/heads/$BRANCH" '/^worktree /{wt=substr($0,10)} $0=="branch "b{print wt}')

if [ -z "$WORKTREE" ]; then
  WORKTREE="$ROOT/.claude/worktrees/$BRANCH"
  git worktree add "$WORKTREE" "$BRANCH" 2>/dev/null \
    || git worktree add -b "$BRANCH" "$WORKTREE"
fi

# --config forces the sandbox definition to be read from the main repo root,
# which is never mounted inside the container — Claude cannot tamper with it.
devcontainer up --workspace-folder "$WORKTREE" --config "$ROOT/.devcontainer/devcontainer.json"

devcontainer exec --workspace-folder "$WORKTREE" --config "$ROOT/.devcontainer/devcontainer.json" claude --dangerously-skip-permissions "$PROMPT"
