# `Metrics` — ETS-Backed Application Metrics Collector

## Overview

This document specifies an Elixir module named `Metrics` that collects application metrics using ETS tables for fast, concurrent-safe storage. The deliverable is the complete implementation in a single file, built on OTP/stdlib only, with no external dependencies.

Counters and gauges coexist in the same table. A metric's type need not be declared upfront: `increment` creates or bumps a counter entry, and `gauge` creates or overwrites a gauge entry.

## Storage and process architecture

The ETS table must be public and registered under the exact name `Metrics` (the module name). It must be created with `read_concurrency: true` and `write_concurrency: true`. Callers may verify all of this via `:ets.info/2`.

This arrangement exists so that `increment` can bypass the GenServer process for maximum throughput — that is, the hot path for incrementing must not serialize through a GenServer `call`. The GenServer is needed only for initialisation and for owning the table.

## API

The public API consists of the following functions.

- `Metrics.start_link(opts \\ [])` — starts the backing GenServer. It accepts a `:name` option for process registration, defaulting to `__MODULE__`.
- `Metrics.increment(name, amount \\ 1)` — atomically increments a named counter by `amount`. Atomicity is achieved with `:ets.update_counter`. Counters are monotonically increasing and never decrease.
- `Metrics.gauge(name, value)` — sets a named gauge to an exact value. Gauges may go up or down freely; each call overwrites the previous value. It returns `:ok` both on create and on overwrite.
- `Metrics.get(name)` — returns the current value of a metric by name, or `nil` if that metric does not exist.
- `Metrics.all()` — returns all metrics as a map of `%{name => value}`.
- `Metrics.reset(name)` — sets a metric back to `0`, regardless of whether it is a counter or a gauge. It returns `:ok`.
- `Metrics.snapshot()` — returns a point-in-time map of all current metrics, identical in shape to `all/0`, but semantically communicating immutability of the returned data.

## Additional interface contract

`Metrics.increment/2` returns `:ok`, not the counter's new value.

## Edge cases

- A negative `amount` passed to `Metrics.increment/2` is out of contract. The function head must be guarded so that such a call raises `FunctionClauseError` and stores nothing.
- An `amount` of `0` is valid: it leaves an existing counter unchanged, and it creates a missing counter at `0`.
- `Metrics.reset(name)` returns `:ok` even for a name that does not exist yet; that name is created at `0`.
- `Metrics.get(name)` yields `nil` for a name that has never been recorded.
