#!/usr/bin/env python3
"""Generate deterministic histories, dependency graphs, and role events.

Expected counts are hand-specified from this fixture's contract; they are not
computed by calling the production algorithms under test.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import subprocess


def write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")


def git(repo: Path, *args: str, env: dict[str, str] | None = None) -> None:
    process_env = os.environ.copy()
    process_env.update({"GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": os.devnull})
    if env:
        process_env.update(env)
    subprocess.run(["git", "-C", str(repo), *args], check=True, env=process_env, stdout=subprocess.DEVNULL)


def generate_history(root: Path) -> None:
    repo = root / "history" / "repo"
    repo.mkdir(parents=True)
    git(repo, "init", "-q", "-b", "main")
    commits = (
        ("Alice", "alice@example.test", "2024-03-10T12:00:00Z", "first", "one\n", "a.txt"),
        ("Bob", "bob@example.test", "2024-06-15T12:00:00Z", "second", "two\n", "b.txt"),
        ("Bob", "bob@example.test", "2025-01-05T12:00:00Z", "third", "three\n", "a.txt"),
    )
    for name, email, timestamp, subject, contents, filename in commits:
        target = repo / filename
        target.write_text(contents, encoding="utf-8")
        git(repo, "add", filename)
        git(
            repo,
            "-c", f"user.name={name}",
            "-c", f"user.email={email}",
            "-c", "commit.gpgsign=false",
            "commit", "-m", subject,
            env={"GIT_AUTHOR_DATE": timestamp, "GIT_COMMITTER_DATE": timestamp},
        )


def generate_graph(root: Path) -> None:
    graph = {
        "schema": "rh-dep-graph/1",
        "ecosystem": "synthetic",
        "nodes": [
            {"id": 0, "name": "root", "version": "1.0.0"},
            {"id": 1, "name": "left", "version": "1.0.0"},
            {"id": 2, "name": "right", "version": "1.0.0"},
            {"id": 3, "name": "shared", "version": "1.0.0"},
            {"id": 4, "name": "leaf", "version": "1.0.0"},
        ],
        "edges": [
            {"from": 0, "to": 1, "scope": "normal"},
            {"from": 0, "to": 2, "scope": "normal"},
            {"from": 1, "to": 3, "scope": "normal"},
            {"from": 2, "to": 3, "scope": "normal"},
            {"from": 3, "to": 4, "scope": "normal"},
            {"from": 4, "to": 3, "scope": "normal"},
        ],
        "unresolved": [],
        "advisories": [],
    }
    write_json(root / "graph" / "input.json", graph)


def generate_roles(root: Path) -> None:
    roles = {
        "schema": "rh-roles-input/1",
        "authorization": {"state": "authorized"},
        "permission_inventory_complete": True,
        "as_of": 200,
        "declarations": [
            {"actor_id": 101, "role": "owner", "permission": 1, "source": "provider", "declared_at": 100},
            {"actor_id": 102, "role": "member", "permission": 4, "source": "file", "declared_at": 110},
            {"actor_id": 103, "role": "maintainer", "permission": 2, "source": "operator", "declared_at": 90, "revoked_at": 150},
        ],
        "observed_actions": [
            {"actor_id": 101, "actor_type": "human", "kind": "release", "at": 120},
            {"actor_id": 103, "actor_type": "human", "kind": "release", "at": 149},
            {"actor_id": 102, "actor_type": "human", "kind": "review", "at": 130},
        ],
        "queries": [
            {"actor_id": 101, "as_of": 99},
            {"actor_id": 101, "as_of": 100},
            {"actor_id": 103, "as_of": 149},
            {"actor_id": 103, "as_of": 150},
        ],
        "permission_queries": [],
    }
    write_json(root / "roles" / "input.json", roles)


def generate(root: Path) -> None:
    root.mkdir(parents=True, exist_ok=True)
    generate_history(root)
    generate_graph(root)
    generate_roles(root)
    # These are independent expected results, intentionally literal.
    write_json(root / "expected.json", {
        "history": {"commits": 3, "distinct_authors": 2, "active_months": 3},
        "graph": {
            "nodes": 5,
            "edges": 6,
            "diamond_join_node": 3,
            "cycle_edges": 1,
            "max_out_degree": 2,
            "max_in_degree": 3,
            "max_in_node": 3,
        },
        "roles": {
            "declarations": 3,
            "owners": 1,
            "members": 1,
            "maintainers": 1,
            "release_events": 2,
            "review_events": 1,
            "effective_boundary": ["unknown", "owner"],
            "revocation_boundary": ["maintainer", "unknown"],
        },
    })


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", required=True, type=Path, help="directory to populate with generated fixtures")
    args = parser.parse_args()
    generate(args.out)


if __name__ == "__main__":
    main()
