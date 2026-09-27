# Agent integration

`rh_cli agent-check` gives coding agents a narrow, machine-readable way to check
whether an exact package identity occurs in a supplied dependency graph,
CycloneDX inventory, or SPDX 2.3 inventory. It does not resolve dependencies
or contact a registry.

```sh
rh_cli agent-check \
  --query query.json \
  --source dependency-graph.json \
  --out result.json
```

A query uses `rh-agent-query/1`. `source_kind` is `dependency_graph`,
`cyclonedx`, or `spdx`; all require exact `name` and `version` strings.
Dependency-graph queries also require an exact `ecosystem` string. Version
ranges and wildcard operators are rejected. Extra prose and unknown fields are
ignored.

Example dependency-graph query:

```json
{
  "schema": "rh-agent-query/1",
  "source_kind": "dependency_graph",
  "ecosystem": "npm",
  "name": "shared",
  "version": "2.0.0"
}
```

The result uses `rh-agent-check-result/1`, includes the source file's SHA-256,
records the query, and returns at most 64 exact matches with a total count and
truncation flag. Status is `found_in_snapshot`, `not_found_in_snapshot`, or
`unsupported_inventory_schema`. Malformed queries and unrecognized source
schemas fail closed with a nonzero exit status.

These statuses describe only the bytes in the named snapshot. A missing record
does not establish that a package is safe or absent from the real dependency
tree; a present record does not approve its use. Agents must use the separate
policy evaluation interface for policy decisions. Repository README text,
comments, and other prose cannot change the lookup or policy rules.
