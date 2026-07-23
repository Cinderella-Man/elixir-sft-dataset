# Debug and repair this module

A colleague shipped the module below for the task described next, and one
behavior bug made it through review. The test suite (not shown here)
produces the failure report at the bottom. Track the bug down and repair
it — keep the diff minimal and leave working code exactly as it is. Reply
with the complete corrected module.

## What the module is supposed to do

# CounterResampler — Specification

## Overview

This document specifies an Elixir module named `CounterResampler`. The module resamples a stream of readings from a **monotonically increasing counter** (think Prometheus-style counters: request totals, bytes sent, etc.) into fixed-interval buckets of **per-interval increase or rate**, with **counter-reset detection**. This is different from a plain aggregator: the values are cumulative, so what matters is the *change* between consecutive samples, not the samples themselves.

The complete module is to be delivered in a single file. It must use only the Elixir standard library, with no external dependencies.

## API

The module exposes the following public API:

- `CounterResampler.resample(data, interval_ms, opts)` — the main entry point. `data` is a list of `{timestamp_ms, counter_value}` tuples (integers and non-negative numbers) at irregular intervals. `interval_ms` is the bucket width in milliseconds. `opts` is a keyword list. It returns a list of `{bucket_start_ms, resampled_value}` tuples sorted ascending by bucket start.

The options are:

- `:mode` — `:delta` (default) emits the total counter increase attributed to the bucket; `:rate` emits that increase divided by the interval length in seconds (`interval_ms / 1000`), yielding a float per-second rate.
- `:reset` — `:detect` (default) or `:raw`. Controls how a decrease between two consecutive samples is interpreted (see the computation rules below).
- `:fill` — `:zero` (default) or `:nil`. How to fill buckets that receive no measured increase.

## Computation rules

- Samples are sorted ascending by timestamp first (input may be unordered).
- Increases are computed between **consecutive samples**. For consecutive samples `(t0, v0)` then `(t1, v1)`, the increment is:
  - `:reset` = `:detect` → if `v1 >= v0`, the increment is `v1 - v0`; if `v1 < v0`, the counter is assumed to have reset, and the increment is taken to be `v1` (the value accumulated since the reset).
  - `:reset` = `:raw` → the increment is always `v1 - v0` (may be negative).
- Each consecutive increment is attributed to the bucket of the **later** sample `t1` (`floor(t1 / interval_ms) * interval_ms`).
- A bucket's value is the **sum** of all increments attributed to it. Because the very first sample has no predecessor, it contributes no increment (a bucket containing only the first sample and nothing else has no measured increase).

## Bucketing rules

- The first bucket starts at the earliest sample timestamp, floored to an `interval_ms` boundary. The last bucket is the one containing the latest sample. Every bucket in between appears in the output.
- For `:delta` mode, a bucket with no attributed increment is `0` under `:fill = :zero` or `nil` under `:fill = :nil`. For `:rate` mode, an empty bucket is `0.0` under `:zero` or `nil` under `:nil`.

## Edge cases

- Empty input → `[]`.
- A single sample → exactly one bucket whose value is the empty/`fill` value (no predecessor, so no measured increase).
- All samples in one bucket → one bucket summing the increments between them.

## Additional interface contract

- `resample/3` validates its arguments: an `interval_ms` that is not a positive integer (e.g. `0`), or a `:mode`/`:reset`/`:fill` option value outside the documented sets (e.g. `mode: :average` or `reset: :ignore`), raises an `ArgumentError`.

## The buggy module

```elixir
defmodule CounterResampler do
  @moduledoc """
  Resamples readings from a monotonically increasing counter into fixed-interval
  buckets of per-interval increase (`:delta`) or per-second rate (`:rate`), with
  optional counter-reset detection.

  Because the samples are cumulative, values are derived from the *change*
  between consecutive samples. Each consecutive increment is attributed to the
  bucket of the later sample, and a bucket's value is the sum of the increments
  attributed to it.
  """

  @type datapoint :: {integer(), number()}
  @type mode :: :delta | :rate
  @type reset :: :detect | :raw
  @type fill :: :zero | nil

  @valid_mode [:delta, :rate]
  @valid_reset [:detect, :raw]
  @valid_fill [:zero, nil]

  @doc """
  Resamples cumulative counter `data` into fixed `interval_ms` buckets.

  `data` is a list of `{timestamp_ms, counter_value}` tuples at irregular
  intervals (unordered input is sorted internally). `interval_ms` is the bucket
  width in milliseconds and must be a positive integer.

  Supported `opts`:

    * `:mode` — `:delta` (default) emits the counter increase attributed to each
      bucket; `:rate` divides that increase by `interval_ms / 1000` seconds.
    * `:reset` — `:detect` (default) treats a decrease between two consecutive
      samples as a counter reset (using the later value as the increment); `:raw`
      keeps the raw difference (which may be negative).
    * `:fill` — `:zero` (default) or `:nil`, choosing how buckets with no measured
      increase are filled.

  Timestamps may be negative; they are floored toward negative infinity onto the
  `interval_ms` grid.

  Arguments are always validated, even for an empty `data` list: a non-positive or
  non-integer `interval_ms`, or an option value outside the documented sets, raises
  an `ArgumentError`.

  Returns a list of `{bucket_start_ms, resampled_value}` tuples sorted ascending
  by bucket start. Empty input returns `[]`.
  """
  @spec resample([datapoint()], pos_integer(), keyword()) :: [{integer(), number() | nil}]
  def resample(data, interval_ms, opts \\ [])

  def resample(data, interval_ms, opts)
      when is_list(data) and is_integer(interval_ms) and interval_ms >= 0 do
    mode = fetch_opt!(opts, :mode, :delta, @valid_mode)
    reset = fetch_opt!(opts, :reset, :detect, @valid_reset)
    fill = fetch_opt!(opts, :fill, :zero, @valid_fill)

    do_resample(data, interval_ms, mode, reset, fill)
  end

  def resample(_data, interval_ms, _opts) do
    raise ArgumentError,
          "interval_ms must be a positive integer, got: #{inspect(interval_ms)}"
  end

  # --------------------------------------------------------------------------
  # Private helpers
  # --------------------------------------------------------------------------

  defp do_resample([], _interval_ms, _mode, _reset, _fill), do: []

  defp do_resample(data, interval_ms, mode, reset, fill) do
    sorted = Enum.sort_by(data, &elem(&1, 0))

    {min_ts, _} = hd(sorted)
    {max_ts, _} = List.last(sorted)

    first_bucket = floor_bucket(min_ts, interval_ms)
    last_bucket = floor_bucket(max_ts, interval_ms)

    increments =
      sorted
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.reduce(%{}, fn [{_t0, v0}, {t1, v1}], acc ->
        inc = increment(v0, v1, reset)
        bucket = floor_bucket(t1, interval_ms)
        Map.update(acc, bucket, inc, &(&1 + inc))
      end)

    first_bucket
    |> Stream.iterate(&(&1 + interval_ms))
    |> Stream.take_while(&(&1 <= last_bucket))
    |> Enum.map(fn bucket_start ->
      value =
        case Map.fetch(increments, bucket_start) do
          {:ok, inc} -> project(inc, mode, interval_ms)
          :error -> empty_value(mode, interval_ms, fill)
        end

      {bucket_start, value}
    end)
  end

  defp increment(v0, v1, :raw), do: v1 - v0

  defp increment(v0, v1, :detect) do
    if v1 < v0, do: v1, else: v1 - v0
  end

  defp project(inc, :delta, _interval_ms), do: inc
  defp project(inc, :rate, interval_ms), do: inc / (interval_ms / 1000)

  defp empty_value(_mode, _interval_ms, nil), do: nil
  defp empty_value(mode, interval_ms, :zero), do: project(0, mode, interval_ms)

  defp floor_bucket(ts, interval_ms), do: Integer.floor_div(ts, interval_ms) * interval_ms

  defp fetch_opt!(opts, key, default, valid) do
    value = Keyword.get(opts, key, default)

    unless value in valid do
      raise ArgumentError,
            "invalid value #{inspect(value)} for option :#{key}; " <>
              "expected one of #{inspect(valid)}"
    end

    value
  end
end
```

## Failing test report

```
2 of 19 test(s) failed:

  * test invalid interval and options raise ArgumentError
      
      
      Expected exception ArgumentError but got ArithmeticError (bad argument in arithmetic expression)
      

  * test argument validation happens even when the data list is empty
      
      
      Expected exception ArgumentError but nothing was raised
```
