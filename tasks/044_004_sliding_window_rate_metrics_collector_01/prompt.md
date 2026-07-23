# Specification: `Metrics` — Sliding-Window Event Rate Collector

## Overview

This document specifies an Elixir module called `Metrics` that collects **time-windowed event rates** using ETS for fast, concurrent-safe storage. Rather than maintaining a single monotonic total, the collector buckets events by the wall-clock second at which they occur, so that callers can ask "how many events happened in the last N seconds?".

The implementation must use only OTP/stdlib — no external dependencies — and must be delivered as a complete implementation in a single file.

## Injectable clock

To keep the collector testable, time must be **injectable**. `start_link` accepts a `:clock` option — a zero-arity function returning the current Unix time in integer seconds — defaulting to `fn -> System.system_time(:second) end`.

## API

The public API must consist of the following functions:

- `Metrics.start_link(opts \\ [])` — starts the backing GenServer. It accepts `:name` (process registration, default `__MODULE__`) and `:clock` (as described above).
- `Metrics.increment(name, amount \\ 1)` — records `amount` events for `name` at the current second, returning `:ok`. `amount` must be a non-negative integer, enforced by a guard clause: a negative or non-integer `amount` raises `FunctionClauseError`, while an `amount` of `0` is accepted and records nothing. This is the hot path and MUST NOT serialize through the GenServer — it must go directly to ETS via `:ets.update_counter`, bumping the per-second bucket for `name`.
- `Metrics.rate(name, window_seconds)` — returns the total number of events recorded for `name` within the last `window_seconds`; that is, all events whose bucket second is strictly greater than `now - window_seconds`, where `now` comes from the injected clock. Returns `0` for an unknown name.
- `Metrics.count(name)` — returns the all-time total number of events recorded for `name` across every bucket, or `0` if nothing has been recorded for `name`.
- `Metrics.reset(name)` — deletes every bucket for `name`.
- `Metrics.prune(retention_seconds)` — deletes all buckets (across every name) whose second is `<= now - retention_seconds`, returning the number of buckets deleted (not the number of events removed). This lets the table be bounded over time.
- `Metrics.all()` — returns a map of `%{name => all_time_total}`, containing only names that currently have buckets.

## Storage and process design

The ETS table must be public and named so that `increment` can bypass the owning process. The GenServer exists only to own the table; the clock is stored so that both the hot path and queries can read it.

## Edge cases

- An `amount` that is negative or not an integer raises `FunctionClauseError`, by virtue of the guard clause.
- An `amount` of `0` is accepted and records nothing.
- `Metrics.rate(name, window_seconds)` counts only buckets whose second is strictly greater than `now - window_seconds`, and returns `0` for an unknown name.
- `Metrics.count(name)` returns `0` if nothing has been recorded for `name`.
- `Metrics.prune(retention_seconds)` removes buckets whose second is `<= now - retention_seconds` and reports the count of deleted buckets, not the count of events removed.
- `Metrics.all()` omits names that currently have no buckets.
