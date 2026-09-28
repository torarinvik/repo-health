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


def generate_history(root: Path, commit_count: int) -> None:
    repo = root / "history" / "repo"
    repo.mkdir(parents=True)
    git(repo, "init", "-q", "-b", "main")
    commit_templates = (
        ("Alice", "alice@example.test", "2024-03-10T12:00:00Z", "first", "one\n", "a.txt"),
        ("Bob", "bob@example.test", "2024-06-15T12:00:00Z", "second", "two\n", "b.txt"),
        ("Bob", "bob@example.test", "2025-01-05T12:00:00Z", "third", "three\n", "a.txt"),
        ("Alice", "alice@example.test", "2025-04-05T12:00:00Z", "fourth", "four\n", "c.txt"),
        ("Bob", "bob@example.test", "2025-07-05T12:00:00Z", "fifth", "five\n", "b.txt"),
        ("Bob", "bob@example.test", "2025-10-05T12:00:00Z", "sixth", "six\n", "a.txt"),
        ("Alice", "alice@example.test", "2026-01-05T12:00:00Z", "seventh", "seven\n", "c.txt"),
        ("Bob", "bob@example.test", "2026-03-05T12:00:00Z", "eighth", "eight\n", "b.txt"),
        ("Bob", "bob@example.test", "2026-05-05T12:00:00Z", "ninth", "nine\n", "a.txt"),
        ("Alice", "alice@example.test", "2026-06-05T12:00:00Z", "tenth", "ten\n", "c.txt"),
        ("Bob", "bob@example.test", "2026-07-05T12:00:00Z", "eleventh", "eleven\n", "b.txt"),
        ("Bob", "bob@example.test", "2026-09-05T12:00:00Z", "twelfth", "twelve\n", "a.txt"),
    )
    for name, email, timestamp, subject, contents, filename in commit_templates[:commit_count]:
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


def generate_graph_chain(root: Path, node_count: int) -> None:
    graph = {
        "schema": "rh-dep-graph/1",
        "ecosystem": "synthetic",
        "nodes": [{"id": index, "name": f"chain-{index}", "version": "1.0.0"} for index in range(node_count)],
        "edges": [{"from": index, "to": index + 1, "scope": "normal"} for index in range(node_count - 1)],
        "unresolved": [],
        "advisories": [],
    }
    write_json(root / "graph" / "chain-input.json", graph)


def generate_roles(root: Path, revoked_at: int) -> None:
    roles = {
        "schema": "rh-roles-input/1",
        "authorization": {"state": "authorized"},
        "permission_inventory_complete": True,
        "as_of": revoked_at + 50,
        "declarations": [
            {"actor_id": 101, "role": "owner", "permission": 1, "source": "provider", "declared_at": 100},
            {"actor_id": 102, "role": "member", "permission": 4, "source": "file", "declared_at": 110},
            {"actor_id": 103, "role": "maintainer", "permission": 2, "source": "operator", "declared_at": 90, "revoked_at": revoked_at},
        ],
        "observed_actions": [
            {"actor_id": 101, "actor_type": "human", "kind": "release", "at": 120},
            {"actor_id": 103, "actor_type": "human", "kind": "release", "at": revoked_at - 1},
            {"actor_id": 102, "actor_type": "human", "kind": "review", "at": 130},
        ],
        "queries": [
            {"actor_id": 101, "as_of": 99},
            {"actor_id": 101, "as_of": 100},
            {"actor_id": 103, "as_of": revoked_at - 1},
            {"actor_id": 103, "as_of": revoked_at},
        ],
        "permission_queries": [],
    }
    write_json(root / "roles" / "input.json", roles)


def generate(root: Path, history_commits: int = 3, graph_chain_nodes: int = 4, role_revoked_at: int = 150) -> None:
    root.mkdir(parents=True, exist_ok=True)
    generate_history(root, history_commits)
    generate_graph(root)
    generate_graph_chain(root, graph_chain_nodes)
    generate_roles(root, role_revoked_at)
    # These are independent expected results, intentionally literal.
    write_json(root / "expected.json", {
        "history": {
            "commits": history_commits,
            "distinct_authors": 1 if history_commits == 1 else 2,
            "active_months": history_commits,
        },
        "graph": {
            "nodes": 5,
            "edges": 6,
            "diamond_join_node": 3,
            "cycle_edges": 1,
            "max_out_degree": 2,
            "max_in_degree": 3,
            "max_in_node": 3,
        },
        "graph_chain": {
            "nodes": graph_chain_nodes,
            "edges": graph_chain_nodes - 1,
            "max_out_degree": 1,
            "max_in_degree": 1,
            "max_in_node": 1,
        },
        "roles": {
            "declarations": 3,
            "owners": 1,
            "members": 1,
            "maintainers": 1,
            "release_events": 2,
            "review_events": 1,
            "revoked_at": role_revoked_at,
            "effective_boundary": ["unknown", "owner"],
            "revocation_boundary": ["maintainer", "unknown"],
        },
    })


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", required=True, type=Path, help="directory to populate with generated fixtures")
    parser.add_argument("--history-commits", type=int, choices=range(1, 13), default=3,
                        help="fixed history size from 1 to 12 commits (default: 3)")
    parser.add_argument("--graph-chain-nodes", type=int, choices=range(2, 33), default=4,
                        help="independent acyclic graph size from 2 to 32 nodes (default: 4)")
    parser.add_argument("--role-revoked-at", type=int, choices=range(91, 1001), default=150,
                        help="maintainer revocation time from 91 to 1,000 (default: 150)")
    args = parser.parse_args()
    generate(args.out, args.history_commits, args.graph_chain_nodes, args.role_revoked_at)


if __name__ == "__main__":
    main()
