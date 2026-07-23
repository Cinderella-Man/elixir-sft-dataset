# MovingAverage — Specification

## Overview

This document specifies an Elixir GenServer module named `MovingAverage`. The module maintains multiple named streams of numeric values and computes Simple Moving Averages (SMA) and Exponential Moving Averages (EMA) on demand.

The complete module is to be delivered in a single file. It must use only the OTP standard library, with no external dependencies.

## API

The public API consists of the following functions:

- `MovingAverage.start_link(opts)` starts the process. It accepts a `:name` option for process registration.

- `MovingAverage.push(server, name, value)` appends a numeric value to the named stream. It returns `:ok`.

- `MovingAverage.get(server, name, type, period)` computes an average over the named stream. `type` is either `:sma` or `:ema`, and `period` is a positive integer for the window size. It returns `{:ok, result}` where result is a float, or `{:error, :no_data}` if no values have been pushed to that name yet.

### SMA semantics

SMA is the arithmetic mean of the last `period` values. If fewer than `period` values have been pushed, the mean of all available values is computed (cold-start behavior).

### EMA semantics

EMA uses the standard multiplier `k = 2 / (period + 1)`. It is computed iteratively over the full history of pushed values: the EMA is seeded with the first value, then for each subsequent value the formula `ema = value * k + prev_ema * (1 - k)` is applied. If fewer than `period` values exist, the EMA is still computed over whatever is available using the same formula. The EMA calculation must always use the full history from the first value pushed, not just the last `period` values — but storing all history to accomplish this should not be necessary. Only the running EMA value per (name, period) pair is stored.

## Memory constraints

Memory constraints are important.

### SMA storage

For SMA, only the last `max_period` values per stream are kept, where `max_period` is the largest period that has ever been requested via `get` for that stream name. Unbounded history is not to be stored. The trimming discipline matters: `push` never trims, and a `get` whose `period` grows `max_period` does **not** trim either — it computes over all the values accumulated so far. Only a `get` whose `period` is at or below the current `max_period` trims the stored values down to the last `max_period` before computing. Concretely: after pushing five values, `get` with period 2 and then period 5 returns the mean of the last 2 and then the mean of all 5 — the period-2 call grew `max_period` and therefore discarded nothing.

The values are to be stored in a field called `values` inside each stream's data, and the per-stream data is kept in a top-level field called `streams` in the GenServer state (i.e. `state.streams["name"].values`).

### EMA storage

For EMA, only the running accumulator per (name, period) pair is stored — the raw values are not stored for EMA purposes. Each time `push` is called, all existing EMA accumulators for that stream are updated. When `get` is called for an EMA period that hasn't been seen before, the EMA is computed from the stored SMA buffer and then the accumulator is registered for future incremental updates.

## Edge cases

- If no values have been pushed to a given name yet, `get` returns `{:error, :no_data}`.

- SMA cold-start: when fewer than `period` values have been pushed, SMA computes the mean of all available values.

- EMA cold-start: when fewer than `period` values exist, the EMA is still computed over whatever is available, using the same formula and the full history from the first value pushed.

- Different stream names must be completely independent — pushing to "sensor:1" must not affect "sensor:2".
