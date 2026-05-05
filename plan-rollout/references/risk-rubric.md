# Risk-tiering rubric

A code change is `low`, `medium`, or `high` risk based on what the diff touches and how recoverable a regression would be. The tier drives:
- Default environment list (low: prod-only; medium: staging+prod; high: all available).
- Checkpoint schedule (see [checkpoint-schedule.md](checkpoint-schedule.md)).
- How aggressively `plan-rollout` asks clarifying questions (high-tier changes never proceed past the ambiguity step with unresolved questions).

## Low

Pure-function changes, doc/typo, behind a flag at 0%, isolated UI tweak, dev-tool changes that don't reach production behaviour.

Examples:
- Added a unit test.
- Fixed a typo in a log message.
- Renamed a private helper that has no callers outside its package.
- Added a feature behind `flag.is("new-x") && false`.
- Changed a CSS class that re-styles one component.

Not low if:
- The change touches the request hot path even cosmetically.
- The change adds or modifies any I/O.

## Medium

API behaviour change, new endpoint, dependency bump (minor), feature flag rollout to ≤10%, isolated background job, single-service refactor that preserves contracts.

Examples:
- New `/api/v1/widgets` endpoint with read-only behaviour.
- Bumped Express from 4.18 to 4.19.
- Added a new Kafka consumer for an existing topic.
- Refactored the authentication middleware to use a different in-memory cache (no contract change).
- Rolling out an existing feature from 5% to 10%.

Not medium if the change touches data at rest, infra, auth contracts, or anything in the hot path that can't be hot-fixed in <30m.

## High

DB migration, schema change, auth/middleware change, infra/IaC change, dependency major bump, code path on the request hot path that can't be hot-fixed in <30m, concurrency primitives, anything that touches money.

Examples:
- Adds a `NOT NULL` column to the `users` table (50M rows).
- Replaces JWT signing key.
- Helm chart migration to a new ingress controller.
- Bumps Postgres driver from v9 to v10.
- Refactors the inner loop of the request router.
- Changes the billing aggregation logic.

Hot-path heuristic: if the change is in the request path of >5% of production traffic and can't be reverted in <30m, it's high. Default to high if you're unsure.

## How to apply

State the tier and one sentence of reasoning. Examples:

- *"Low — typo fix in a log message, no behaviour change."*
- *"Medium — new endpoint behind feature flag, rollout to 10% planned."*
- *"High — adds a NOT NULL column to a 50M-row table; backfill is the riskiest part and can't be hot-fixed."*

The reasoning is what makes the tier defensible later. Don't skip it.
