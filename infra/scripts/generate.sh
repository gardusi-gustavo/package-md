#!/usr/bin/env bash
# Implement one issue with opencode. Called by the generate workflow.
set -euo pipefail

issue="${1:?issue number}"
repo="${GITHUB_REPOSITORY:?}"
model="${OPENCODE_MODEL:-deepseek/deepseek-flash}"

title="$(gh issue view "$issue" --repo "$repo" --json title --jq .title)"
body="$(gh issue view "$issue" --repo "$repo" --json body --jq .body)"

if ! command -v opencode >/dev/null 2>&1; then
  npm install -g opencode-ai
fi

prompt="Implement issue #${issue} in this repository.

Title: ${title}

Body:
${body}

Rules:
- read AGENTS.md and follow it;
- make the smallest change that satisfies the issue;
- do not modify .github/workflows/**;
- run the repository tests before finishing;
- do not commit; the workflow commits."

opencode run --model "$model" --auto "$prompt"
