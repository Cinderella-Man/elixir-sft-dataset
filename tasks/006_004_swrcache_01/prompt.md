# Design Brief: `SwrCache` — a Stale-While-Revalidate GenServer

## Problem

Traditional TTL caches have a single cliff — past the TTL, the entry is gone and the next reader waits for a recompute. Stale-While-Revalidate (SWR), as used by HTTP caches, Cloudflare, React Query, and SWR.js, introduces a second tier: past `fresh_until` the entry is served as **stale** while a background revalidation recomputes it; past `stale_until` the entry is dropped entirely and becomes a hard miss. This lets fast paths serve traffic immediately with bounded staleness, while async revalidation keeps the cache hot.

The distinction from refresh-ahead is semantic: SWR tells the caller the freshness of what they got, and the "stale" tier is bounded by its own timeout, not by a fraction of the fresh TTL.

The deliverable is an Elixir GenServer module called `SwrCache` that implements SWR caching with two independent freshness tiers.

## Constraints

- Deliver the complete module in a single file.
- Use only the OTP standard library — no external dependencies.
- The two freshness tiers are independent: the "stale" tier is bounded by its own timeout, not by a fraction of the fresh TTL.

## Required interface

1. `SwrCache.start_link(opts)`, accepting:
   - `:name` — optional process registration
   - `:clock` — `(-> integer())` current time in ms (default `fn -> System.monotonic_time(:millisecond) end`)
   - `:sweep_interval_ms` — periodic sweep of fully-expired entries, in ms (default `60_000`; `:infinity` disables)

2. `SwrCache.put(server, key, value, fresh_ms, stale_ms, loader)`, where:
   - `fresh_ms` is how long the entry is considered **fresh** (served directly, no revalidation)
   - `stale_ms` is how much additional time past `fresh_until` the entry is served as **stale** while revalidation runs. The entry is hard-deleted at `fresh_until + stale_ms`.
   - `loader` is a zero-arity function invoked asynchronously to produce a new value during revalidation. Its result replaces the entry with a new `fresh_ms` clock.
   - Both `fresh_ms` and `stale_ms` must be positive integers; enforce this with function-head guards so that a non-positive or non-integer argument raises `FunctionClauseError`. If the key already exists, all four — value, fresh_ms, stale_ms, loader — are overwritten.
   - Returns `:ok`.

3. `SwrCache.get(server, key)`, with a three-way return shape:
   - `{:ok, value, :fresh}` — within the fresh window, no revalidation triggered
   - `{:ok, value, :stale}` — within the stale window; a revalidation is triggered if not already in flight for this key, and the current (stale) value is returned
   - `:miss` — no entry, or the entry is past its hard-expiry (`fresh_until + stale_ms`). In the latter case the entry is lazily evicted on this read.

   The three-way return is deliberate — callers often want to distinguish a fresh value from a stale-but-acceptable one (e.g. to show a "refreshing..." indicator, or to skip a stale value and force a synchronous recompute). This is the defining API shape of SWR vs a plain TTL cache.

4. `SwrCache.delete(server, key)` — removes the entry and invalidates any in-flight revalidation for that key (i.e. the revalidation's result, when it arrives, will be discarded). Returns `:ok` regardless of existence.

5. `SwrCache.stats(server)` — returns `%{entries: non_neg_integer, revalidations_in_flight: non_neg_integer}`.

6. Sending the server process a bare `:sweep` message performs one sweep pass immediately — the same work the periodic timer performs.

## Revalidation machinery (similar to refresh-ahead but with SWR semantics)

When `get/2` observes that an entry is in the stale window AND no revalidation is already in flight for that key:

1. Mark the key as "revalidation in flight" with a unique `task_ref`.
2. Spawn a task that calls the loader and sends `{:revalidate_complete, key, task_ref, new_value}` to the GenServer, or `{:revalidate_failed, key, task_ref, reason}` on error/raise/throw.

The GenServer handles the result:

- `{:revalidate_complete, key, task_ref, new_value}` — if the key still exists AND the in-flight ref still matches, apply the new value with a **fresh `fresh_ms` and `stale_ms` drawn from the current entry** (revalidation preserves the original tier durations) measured from the completion time. Clear the in-flight marker. Otherwise discard.

- `{:revalidate_failed, key, task_ref, reason}` — clear the in-flight marker if it matches. The entry stays in its current state — still stale, which means the next stale read will trigger another revalidation.

A `put` that overwrites invalidates any in-flight revalidation (same mechanism as the refresh-ahead variant) so a stale result can't clobber the new value.

The periodic sweep removes only fully-expired (past-stale) entries. Entries in the stale window are kept in state because the next reader triggers a revalidation from them. A stale entry with a failed revalidation is NOT eagerly dropped by sweep — it remains until it passes hard expiry.

## Acceptance criteria

Hard expiry vs stale tier — careful math. With `fresh_ms = 1000` and `stale_ms = 2000`, a put at t=0 yields:

- t ∈ [0, 1000): fresh — return `{:ok, value, :fresh}`, no revalidation
- t ∈ [1000, 3000): stale — return `{:ok, value, :stale}`, trigger revalidation if not in flight
- t ≥ 3000: hard expired — return `:miss`, lazily evict
