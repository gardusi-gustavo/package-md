# Repository bootstrap

Status: **staged locally**. GitHub-side rulesets are applied after the mirror exists.

- Default branch: `main`
- Squash merge only; linear history
- One human approval
- Tags: `v*` protected
- Secret scanning: GitHub native

```json
{
  "repository": "gardusi-gustavo/package-md",
  "default_branch": "main",
  "required_approvals": 1,
  "squash_merge": true,
  "linear_history": true,
  "secret_scanning": "pending",
  "tag_pattern": "v*"
}
```
