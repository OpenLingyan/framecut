#!/usr/bin/env python3
"""Validate that repository collaboration metadata uses ASCII English text."""

from __future__ import annotations

import os
import subprocess
import sys


def git(*arguments: str) -> str:
    result = subprocess.run(
        ["git", *arguments],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    return result.stdout.rstrip("\n")


def commit_exists(revision: str) -> bool:
    return subprocess.run(
        ["git", "cat-file", "-e", f"{revision}^{{commit}}"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    ).returncode == 0


def find_non_ascii(value: str) -> tuple[int, str] | None:
    for index, character in enumerate(value):
        if ord(character) > 0x7F:
            return index, character
    return None


def validate_ascii(label: str, value: str, errors: list[str]) -> None:
    match = find_non_ascii(value)
    if match is None:
        return

    index, character = match
    errors.append(
        f"{label} contains non-ASCII character U+{ord(character):04X} "
        f"at position {index + 1}. Use English with plain ASCII punctuation."
    )


def commits_to_check(base_sha: str, head_sha: str) -> list[str]:
    zero_sha = "0" * 40
    if base_sha and base_sha != zero_sha and commit_exists(base_sha):
        revisions = git("rev-list", "--reverse", f"{base_sha}..{head_sha}")
        return revisions.splitlines() if revisions else []
    return [head_sha]


def main() -> int:
    errors: list[str] = []
    event_name = os.environ.get("FRAMECUT_EVENT_NAME", "local")
    branch_name = os.environ.get("FRAMECUT_HEAD_REF") or git(
        "branch", "--show-current"
    )
    head_sha = os.environ.get("FRAMECUT_HEAD_SHA") or git("rev-parse", "HEAD")
    base_sha = os.environ.get("FRAMECUT_BASE_SHA", "")

    validate_ascii("Branch name", branch_name, errors)

    if event_name == "pull_request":
        validate_ascii(
            "Pull request title", os.environ.get("FRAMECUT_PR_TITLE", ""), errors
        )
        validate_ascii(
            "Pull request description",
            os.environ.get("FRAMECUT_PR_BODY", ""),
            errors,
        )

    for commit_sha in commits_to_check(base_sha, head_sha):
        message = git("show", "--no-patch", "--format=%B", commit_sha)
        validate_ascii(f"Commit {commit_sha[:12]} message", message, errors)

    if errors:
        print("Repository metadata language policy failed:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1

    print("Repository metadata language policy passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
