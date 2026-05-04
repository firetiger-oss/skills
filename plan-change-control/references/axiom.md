# Axiom (telemetry source)

## Detection

Axiom is **priority-3**. Detect via:
- MCP tools matching `Axiom:*` (e.g. `Axiom:run_query`, `Axiom:list_datasets`).
- The `axiom` CLI on `$PATH`.
- `AXIOM_TOKEN` + `AXIOM_ORG_ID` env vars.

## Indicator query patterns

Axiom uses APL (Axiom Processing Language), a Kusto-like query language.

### Error ratio (golden signal: errors)

```
kind: ratio
source: Axiom:run_query
query: |
  ['my-svc']
  | where _time > ago(24h)
  | summarize errors = countif(level == "error"), total = count() by env
  | extend error_ratio = errors / total
```

### Latency p99

```
kind: gauge
source: Axiom:run_query
query: |
  ['my-svc']
  | where _time > ago(24h)
  | summarize p99 = percentile(duration_ms, 99) by env
```

### Traffic

```
kind: gauge
source: Axiom:run_query
query: |
  ['my-svc']
  | where _time > ago(24h)
  | summarize requests = count() by env
```

### Intended effect (cache hit ratio)

```
kind: ratio
source: Axiom:run_query
query: |
  ['my-svc']
  | where _time > ago(24h)
  | summarize hits = countif(cache_hit == true), total = count() by env
  | extend hit_ratio = hits / total
```

## Querying the 24-hour baseline

The `where _time > ago(24h)` predicate gives you the 24h window. Capture per-env values into the plan baseline block.

## MCP tool reference

Use `Axiom:` prefix. APL syntax does not vary across Axiom tiers.

## Common pitfalls

- **Forgetting `_time` filter.** Without it, queries scan the entire dataset.
- **`summarize ... by env` requires `env` to be a column.** If env is in a nested map, project it out first: `extend env = tostring(metadata.env)`.
- **Quoting dataset names.** Use `['dataset-name']` for any name containing hyphens.
