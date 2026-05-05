# Evidence-discipline hard gate

## Contents
- Why bias toward false negatives
- The four checks (verbatim)
- Variance test (the fifth check, applied implicitly)
- Volume correlation
- Seasonality patterns
- Worked examples
- When to override the gate

## Why bias toward false negatives

False positives in change monitoring are extremely expensive:
- They cause unnecessary rollbacks (or worse, panicked rollbacks that introduce their own bugs).
- They erode user trust: after the third "monitoring said it failed but it was fine" the user stops paying attention.
- They train the agent to over-report, which compounds.

False negatives — slow regressions that the executor declares "no issue" when there was a subtle one — are bad too, but recoverable. The next checkpoint, the SLO alert, or a human will catch them. The executor's job is to be the *first* high-confidence signal, not the only signal.

So: at every checkpoint, before declaring `regressed`, every indicator must pass the four-check gate. Any failure ⇒ `INCONCLUSIVE`, not `regressed`.

## The four checks

These are ported verbatim from the closed-source product's `agent/src/firetiger/agent/plan_executor_agent.py`. Apply each check per indicator per environment.

### Check 1: ≥24h pre-deploy baseline

The plan should have captured a 24-hour baseline at write time. The executor verifies the baseline:
- Is at least 24 hours of data, ending at a point before `deploy_time`.
- If the telemetry source has shorter retention (some teams keep < 24h on cheaper tiers), state the explicit retention limit in the report and proceed.
- If no baseline at all (the plan flagged `baseline: pending`), the indicator is `INCONCLUSIVE` regardless.

### Check 2: Same-time-of-day comparison

The post-deploy reading must be compared to the **same time of day on at least one prior day** (24h ago, ideally also 48h ago and 168h-ago = same day-of-week one week ago). Specifically:

- Take the post-deploy reading at, say, `T = deploy_time + 30m`.
- Compare to readings at `T - 24h`, `T - 48h`, and (when 7 days of data exists) `T - 168h`.
- If the post-deploy reading falls within the range of those prior-day readings, it's likely a periodic pattern, not a regression.

Why this matters: a service that handles peak traffic at 9 AM PT will have higher latency at 9 AM PT every day. A deploy at 8:45 AM PT followed by a checkpoint at 9:30 AM PT will see a latency spike — not because of the deploy, but because of the daily cycle. Without same-time-of-day comparison, you'd false-positive that as a regression.

### Check 3: Analytical reason

The agent must articulate (in one line) why the post-deploy reading is *not* explained by:
- The intended effect of the change (a change that fixes a bug should *show* the error rate falling — that's not a regression, it's confirmation).
- Routine variance (the metric was already noisy pre-deploy at the same magnitude).
- Volume correlation (request count tracks daily cycle; the metric drop is just less traffic, not better behaviour).
- Seasonality (cron-driven jobs, weekly batch windows, business-hours/off-hours patterns).

If the agent cannot articulate this reason — even an honest "I don't know why this is anomalous" — the verdict is `INCONCLUSIVE`. The reason field is what makes the verdict defensible later.

### Check 4: Variance test

If the pre-deploy baseline already shows >30% noise (the indicator's value within the 24h baseline window varies by more than 30% of the threshold delta), treat post-deploy movement of similar magnitude as routine variance, not a regression.

Concretely: if `error_rate` baseline was 0.18% with a 24h range of 0.10% to 0.32% (variance ≈ 0.22%), a post-deploy reading of 0.30% is within normal noise, even if your threshold was "5× baseline = 0.9%". The threshold catches large excursions; the variance test rejects small ones that just look anomalous because the baseline is noisy.

The exact 30% number is calibrated against production data; it can be relaxed (for very stable indicators) or tightened (for SLO-grade SLIs) by stating it explicitly in the indicator's `notes` field on the plan.

## Volume correlation

Specifically called out because it's the most common false-positive source:

If a metric is volume-sensitive (count of errors, count of slow requests, queue depth at peak hours), a drop in traffic can make the metric drop in a way that looks like an improvement. Conversely, a traffic spike can make the metric rise in a way that looks like a regression.

Always express SLI-style indicators as **ratios** (good_events / total_events) which factor out volume — see [`indicator-design.md`](../../plan-rollout/references/indicator-design.md). For gauges where the metric *is* a count, the analytical-reason check (3) must explicitly address volume: "post-deploy request count is 80% of baseline, so the error count drop tracks volume, not behaviour."

## Seasonality patterns

Common patterns to recognise:

| Pattern | Hint |
|---------|------|
| Daily | Lunch dip (12 PM PT US-traffic), peak hours (9 AM, 3 PM) |
| Weekly | Weekend traffic drop, Monday morning ramp |
| Cron-driven | Batch job at midnight UTC; replication catch-up at 4 AM |
| Release cycles | Deploy windows themselves (Tuesday/Thursday afternoons) cause subtle baseline shifts |

The same-time-of-day comparison handles daily patterns. Weekly patterns need 7-day-prior comparison; cron-driven patterns need an explicit reason in the analytical-reason field.

## Worked examples

### Example A: legitimate regression

- Indicator: `error-rate-checkout`, `kind: ratio`, baseline 0.18% over 24h.
- Post-deploy reading at +30m: 1.2%.
- Same-time-of-day prior days: 0.16%, 0.21% (both well under 0.5%).
- Pre-deploy noise: range 0.10–0.32% (variance ≈ 0.22%).
- Threshold: > 5× baseline = > 0.9%.
- Reading is 1.2% > 0.9% threshold ✓; not in prior-day range ✓; variance can't explain it ✓.
- Analytical reason: "post-deploy error rate is 6.7× baseline, not seen on prior days at the same hour, baseline noise insufficient to explain — likely caused by the new endpoint's validation logic."
- Verdict: **regressed**.

### Example B: false positive — periodic pattern

- Indicator: `latency-p99-search`, `kind: gauge`, baseline 280ms p99 over 24h, with a daily peak around 09:00 PT reaching 480ms.
- Deploy at 08:50 PT; checkpoint at 09:20 PT reads 460ms.
- Same-time-of-day prior days: 470ms, 485ms.
- Reading 460ms is within prior-day range.
- Verdict: **INCONCLUSIVE** (or the same-time-of-day check passes ⇒ unchanged). Not a regression.

### Example C: false positive — variance

- Indicator: `error-rate-experiment-svc`, baseline 1.4% over 24h, range 0.6%–2.1%.
- Threshold: > 3× baseline = > 4.2%.
- Post-deploy reading at +10m: 2.0%.
- Threshold not crossed; even if it were, variance test would catch it.
- Verdict: **unchanged**.

### Example D: intended effect, not a regression

- Indicator: `error-rate-checkout`, `direction: intended-down` (the change is supposed to *fix* a bug that causes errors).
- Post-deploy reading at +30m: 0.05% (down from 0.18% baseline).
- Same-time-of-day prior days: 0.16%, 0.20%.
- Verdict: **intended-confirmed**, not regressed. The drop is the intent.

## When to override the gate

Don't, unless the user explicitly says so. The gate exists to prevent the executor from over-reporting; loosening it without a reason just produces noise. If the user wants to flag *any* deviation as worth investigating (e.g. for a high-stakes deploy where they prefer false positives), they can add a `strict-mode` note on the plan; the executor will then treat any threshold crossing as `regressed` without the same-time-of-day or variance checks. This is rare and should be agreed with the user explicitly.
