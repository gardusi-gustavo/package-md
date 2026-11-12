# Contributing

Small, reviewable changes. One issue, one pull request.

## Workflow

1. Open or claim an issue that states the outcome and the acceptance check.
2. Create a branch from `main`.
3. Make the smallest change that satisfies the issue.
4. Open a pull request that references the issue.
5. Wait for CI. A human reviews and merges.

`main` is protected: no direct pushes, no force pushes, squash merges only.

## Limits

- at most 4 files and 250 changed lines per pull request;
- at most 5 commits per pull request;
- one pull request per issue;
- if the change grows, split the issue instead of growing the diff.

## Conventions

- keep secrets, tokens, and personal data out of the repository;
- prefer appending over rewriting; history is the record;
- add tests or a verification step for every behavioural change;
- run the repository CI locally before opening the pull request.

## Review

Reviews check correctness, evidence, scope, tests, and rollback. A request for
changes is normal; answer with a new commit, not a rewritten branch.
