#!/usr/bin/env python3
"""Distribute the default community health files to every repository.

Templates live in ``docs/templates/community`` and are written to
``.github/<name>`` in each target repository, a location GitHub recognises and
every repository's file policy already allows.

Usage:

    sync_community.py --check
    sync_community.py --check --json
    sync_community.py --apply --yes
    sync_community.py --apply --yes --repo package-go
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import subprocess
import sys

def _gh_home() -> pathlib.Path:
    env = os.environ.get("GH_HOME")
    if env:
        return pathlib.Path(env)
    candidates = [
        pathlib.Path.home() / ".config" / "gh",
        pathlib.Path("/data/data/com.termux/files/home/.config/gh"),
    ]
    for candidate in candidates:
        if (candidate / "registry.json").exists():
            return candidate
    return candidates[0]


GH_HOME = _gh_home()
REGISTRY = pathlib.Path(os.environ.get("WORKSPACE_GH_REGISTRY", GH_HOME / "registry.json"))
TEMPLATES = pathlib.Path(__file__).resolve().parents[3] / "docs" / "templates" / "community"
FILES = ["CONTRIBUTING.md", "SECURITY.md", "CODE_OF_CONDUCT.md"]
BRANCH = "docs/community-defaults"
EXCLUDE = {
    "gardusi-gustavo/.github",
    "gardusi-gustavo/gardusi-gustavo",
}


def registry() -> dict:
    return json.loads(REGISTRY.read_text(encoding="utf-8"))


def repos(reg: dict, only: list[str] | None = None):
    for domain in reg.get("domains", []):
        for repo in domain.get("repos", []):
            name = repo["github"].split("/")[-1]
            if only and name not in only:
                continue
            if repo["github"] in EXCLUDE:
                continue
            path = pathlib.Path(repo["path"])
            if path.is_dir():
                yield repo["github"], domain["config_dir"], path


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()[:12]


def state(path: pathlib.Path) -> tuple[str, list[str]]:
    drifted = []
    for name in FILES:
        target = path / ".github" / name
        wanted = (TEMPLATES / name).read_bytes()
        if not target.exists() or target.read_bytes() != wanted:
            drifted.append(name)
    return ("ok" if not drifted else "drift"), drifted


def run(args: list[str], cwd: pathlib.Path) -> subprocess.CompletedProcess:
    return subprocess.run(args, cwd=cwd, text=True, capture_output=True, timeout=300)


def gh(args: list[str], config_dir: str) -> subprocess.CompletedProcess:
    env = dict(os.environ, GH_CONFIG_DIR=config_dir)
    return subprocess.run(["gh", *args], text=True, env=env, capture_output=True, timeout=180)


def check(reg: dict, only: list[str], as_json: bool) -> int:
    rows = []
    for slug, _cfg, path in repos(reg, only):
        status, drifted = state(path)
        rows.append({"repo": slug, "state": status, "files": drifted})
    if as_json:
        print(json.dumps(rows, indent=2))
    else:
        for row in rows:
            print(f"{row['repo']:55} {row['state']:6} {','.join(row['files'])}")
        print(f"\n{len(rows)} repositories, {sum(r['state'] != 'ok' for r in rows)} need files")
    return 0


def apply_one(slug: str, cfg: str, path: pathlib.Path, yes: bool) -> str:
    status, drifted = state(path)
    if status == "ok":
        return "ok"
    if not yes:
        print(f"[dry-run] {slug}: would write {', '.join(drifted)}")
        return "planned"
    run(["git", "checkout", "-B", BRANCH], path)
    for name in drifted:
        target = path / ".github" / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes((TEMPLATES / name).read_bytes())
        run(["git", "add", str(target)], path)
    commit = run(["git", "commit", "-m", "Add the default community health files"], path)
    if commit.returncode != 0:
        return "commit failed"
    push = run(["git", "push", "git@github.com:" + slug + ".git", f"HEAD:refs/heads/{BRANCH}"], path)
    if push.returncode != 0:
        return f"push failed: {push.stderr.strip()[:60]}"
    pr = gh(["pr", "create", "--repo", slug, "--base", "main", "--head", BRANCH,
             "--title", "Add the default community health files",
             "--body", "Adds CONTRIBUTING, SECURITY, and CODE_OF_CONDUCT under .github/, "
                       "sourced from gardusi-gustavo/package-md."], cfg)
    if pr.returncode != 0:
        return f"pr failed: {pr.stderr.strip()[:60]}"
    return pr.stdout.strip().splitlines()[-1]


def apply(reg: dict, only: list[str], yes: bool) -> int:
    for slug, cfg, path in repos(reg, only):
        try:
            print(f"{slug:55} {apply_one(slug, cfg, path, yes)}")
        except Exception as exc:
            print(f"{slug:55} error: {exc}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(prog="sync_community.py", description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--check", action="store_true")
    group.add_argument("--apply", action="store_true")
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--yes", action="store_true")
    parser.add_argument("--repo", action="append", default=[])
    args = parser.parse_args()
    reg = registry()
    if args.check:
        return check(reg, args.repo, args.json)
    return apply(reg, args.repo, args.yes)


if __name__ == "__main__":
    raise SystemExit(main())
