# Implement the missing function

The specification below is followed by its complete, tested solution —
minus `aggregate`, whose clause bodies are all `# TODO`. Supply that one
function; the rest of the module is fixed and must stay exactly as shown.

## The task

# Design Brief: `StreamingResampler`

## Problem

Build an Elixir module called `StreamingResampler` — a **GenServer** that performs **online, streaming** resampling of a `{timestamp, value}` point stream into fixed-interval buckets. Unlike a batch resampler, it never sees the whole data set at once: points are pushed one at a time, and buckets are **finalized (emitted) as an event-time watermark advances**, with support for bounded late-arriving data.

## Constraints

- Deliver the complete module in a single file.
- Use only the Elixir standard library (GenServer is fine), no external dependencies.

## Configuration Options

- `:agg` — aggregation mode, one of `:last`, `:first`, `:mean`, `:sum`, `:count`, `:max`, `:min`. Defaults to `:last`.
- `:fill` — gap-filling for empty buckets that get finalized: `:nil` or `:forward`. Defaults to `:nil`.
- `:allowed_lateness` — a non-negative integer number of milliseconds. Defaults to `0`.

## Required Interface

1. `StreamingResampler.start_link(interval_ms, opts)` — start the server. `interval_ms` is the bucket width in milliseconds. `opts` is optional and defaults to `[]`, so `start_link(interval_ms)` must also work. Returns `{:ok, pid}`. Raises `ArgumentError` for an invalid `interval_ms` or invalid options.
2. `StreamingResampler.push(pid, timestamp_ms, value)` — ingest one data point. Returns `:ok`. The **watermark** is the maximum timestamp ever seen. Pushing advances the watermark and may finalize buckets.
3. `StreamingResampler.finalized(pid)` — return the list of buckets finalized *so far*, as `{bucket_start_ms, aggregated_value}` tuples sorted ascending by bucket start.
4. `StreamingResampler.flush(pid)` — force-finalize every still-open bucket up to and including the bucket containing the current watermark, then return the full sorted list of all finalized buckets.
5. `StreamingResampler.stats(pid)` — return a map with at least `:late_dropped` (count of dropped late points), `:watermark`, and `:open_buckets` (number of not-yet-finalized buckets currently buffered).

## Semantics

- A point at timestamp `t` belongs to the bucket with start `floor(t / interval_ms) * interval_ms`.
- The grid's first bucket is fixed by the **first point ever pushed** (floored to a boundary). Emission proceeds contiguously from there — every grid bucket is finalized in ascending order with no gaps, including empty ones (subject to `:fill`).
- A bucket `[start, start + interval_ms)` is finalized once `watermark >= start + interval_ms + allowed_lateness`. Finalizing empty buckets uses the `:fill` policy (`:forward` carries the last finalized non-nil aggregate; a leading gap is `nil`).
- A point whose bucket has **already been finalized** (its bucket start is earlier than the next bucket awaiting emission) is a *late drop*: it is discarded and counted in `:late_dropped`. Late points that still fall inside an open bucket (thanks to `:allowed_lateness`) are accepted and included in that bucket's aggregate.
- Aggregation follows the usual rules: `:last`/`:first` by timestamp within the bucket (points may arrive out of order — order by timestamp internally), `:mean` (float), `:sum`, `:count` (integer), `:max`, `:min`.

## Acceptance Criteria

- `finalized/1` and `flush/1` before any push return `[]`; `stats/1` reports a `nil` watermark.
- After `flush/1`, any subsequently pushed point belonging to an already-emitted bucket is a late drop.

## The module with `aggregate` missing

```elixir
defmodule StreamingResampler do
  @moduledoc """
  A GenServer that resamples a streaming `{timestamp, value}` point stream into
  fixed-interval buckets online, finalizing buckets as an event-time watermark
  advances and tolerating bounded late-arriving data.

  The watermark is the maximum timestamp ever pushed. A bucket
  `[start, start + interval)` is finalized once
  `watermark >= start + interval + allowed_lateness`. Buckets are emitted
  contiguously in ascending order (empty ones included, subject to `:fill`).
  A point whose bucket has already been emitted is dropped and counted.
  """

  use GenServer

  @valid_agg [:last, :first, :mean, :sum, :count, :max, :min]
  @valid_fill [nil, :forward]

  # --------------------------------------------------------------------------
  # Client API
  # --------------------------------------------------------------------------

  @doc """
  Start the streaming resampler.

  `interval_ms` is the bucket width in milliseconds and must be a positive
  integer. Options:

    * `:agg` — aggregation mode, one of `#{inspect(@valid_agg)}` (default `:last`)
    * `:fill` — gap-fill policy, one of `#{inspect(@valid_fill)}` (default `:nil`)
    * `:allowed_lateness` — non-negative integer milliseconds (default `0`)

  Raises `ArgumentError` for an invalid `interval_ms` or invalid options.
  """
  @spec start_link(pos_integer(), keyword()) :: GenServer.on_start()
  def start_link(interval_ms, opts \\ []) do
    unless is_integer(interval_ms) and interval_ms > 0 do
      raise ArgumentError, "interval_ms must be a positive integer, got: #{inspect(interval_ms)}"
    end

    _ = fetch_opt!(opts, :agg, :last, @valid_agg)
    _ = fetch_opt!(opts, :fill, nil, @valid_fill)

    lateness = Keyword.get(opts, :allowed_lateness, 0)

    unless is_integer(lateness) and lateness >= 0 do
      raise ArgumentError,
            "allowed_lateness must be a non-negative integer, got: #{inspect(lateness)}"
    end

    GenServer.start_link(__MODULE__, {interval_ms, opts})
  end

  @doc """
  Ingest one `{timestamp_ms, value}` data point.

  Advances the watermark (the maximum timestamp seen) and may finalize buckets.
  A point mapping to an already-finalized bucket is dropped and counted as late.
  Returns `:ok`.
  """
  @spec push(GenServer.server(), integer(), number()) :: :ok
  def push(pid, timestamp_ms, value) when is_integer(timestamp_ms) do
    GenServer.call(pid, {:push, timestamp_ms, value})
  end

  @doc """
  Return the buckets finalized so far as `{bucket_start_ms, aggregated_value}`
  tuples, sorted ascending by bucket start.
  """
  @spec finalized(GenServer.server()) :: [{integer(), number() | nil}]
  def finalized(pid), do: GenServer.call(pid, :finalized)

  @doc """
  Force-finalize every still-open bucket up to and including the bucket
  containing the current watermark, then return the full sorted list of all
  finalized buckets.
  """
  @spec flush(GenServer.server()) :: [{integer(), number() | nil}]
  def flush(pid), do: GenServer.call(pid, :flush)

  @doc """
  Return a map of runtime statistics with `:late_dropped`, `:watermark`, and
  `:open_buckets` (the number of not-yet-finalized buckets currently buffered).
  """
  @spec stats(GenServer.server()) :: map()
  def stats(pid), do: GenServer.call(pid, :stats)

  # --------------------------------------------------------------------------
  # Server callbacks
  # --------------------------------------------------------------------------

  @impl true
  def init({interval_ms, opts}) do
    state = %{
      interval: interval_ms,
      lateness: Keyword.get(opts, :allowed_lateness, 0),
      agg: fetch_opt!(opts, :agg, :last, @valid_agg),
      fill: fetch_opt!(opts, :fill, nil, @valid_fill),
      open: %{},
      emitted: [],
      next_emit: nil,
      last_value: nil,
      late_dropped: 0,
      watermark: nil
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:push, ts, value}, _from, state) do
    state = ensure_started(state, ts)
    state = %{state | watermark: bump(state.watermark, ts)}
    bucket = floor_bucket(ts, state.interval)

    state =
      if bucket < state.next_emit do
        %{state | late_dropped: state.late_dropped + 1}
      else
        open = Map.update(state.open, bucket, [{ts, value}], &[{ts, value} | &1])
        %{state | open: open}
      end

    {:reply, :ok, finalize(state)}
  end

  def handle_call(:finalized, _from, state) do
    {:reply, Enum.reverse(state.emitted), state}
  end

  def handle_call(:flush, _from, state) do
    state = flush_all(state)
    {:reply, Enum.reverse(state.emitted), state}
  end

  def handle_call(:stats, _from, state) do
    stats = %{
      late_dropped: state.late_dropped,
      watermark: state.watermark,
      open_buckets: map_size(state.open)
    }

    {:reply, stats, state}
  end

  # --------------------------------------------------------------------------
  # Finalization
  # --------------------------------------------------------------------------

  defp ensure_started(%{next_emit: nil} = state, ts) do
    %{state | next_emit: floor_bucket(ts, state.interval)}
  end

  defp ensure_started(state, _ts), do: state

  defp finalize(%{next_emit: nil} = state), do: state

  defp finalize(state) do
    if state.next_emit + state.interval + state.lateness <= state.watermark do
      state
      |> close_bucket(state.next_emit)
      |> advance()
      |> finalize()
    else
      state
    end
  end

  defp flush_all(%{next_emit: nil} = state), do: state

  defp flush_all(state) do
    last_bucket = floor_bucket(state.watermark, state.interval)
    do_flush(state, last_bucket)
  end

  defp do_flush(state, last_bucket) do
    if state.next_emit <= last_bucket do
      state
      |> close_bucket(state.next_emit)
      |> advance()
      |> do_flush(last_bucket)
    else
      state
    end
  end

  defp advance(state), do: %{state | next_emit: state.next_emit + state.interval}

  defp close_bucket(state, bucket) do
    agg_value =
      case Map.fetch(state.open, bucket) do
        {:ok, points} -> points |> Enum.sort_by(&elem(&1, 0)) |> aggregate(state.agg)
        :error -> nil
      end

    filled =
      case {agg_value, state.fill} do
        {nil, :forward} -> state.last_value
        {nil, nil} -> nil
        {v, _} -> v
      end

    last_value = if agg_value != nil, do: agg_value, else: state.last_value

    %{
      state
      | open: Map.delete(state.open, bucket),
        emitted: [{bucket, filled} | state.emitted],
        last_value: last_value
    }
  end

  # --------------------------------------------------------------------------
  # Helpers
  # --------------------------------------------------------------------------

  defp bump(nil, ts), do: ts
  defp bump(current, ts), do: max(current, ts)

  # Integer.floor_div/2 rounds toward negative infinity, so negative timestamps
  # land in the bucket below them (e.g. -500 with a 1000ms grid -> -1000).
  defp floor_bucket(ts, interval), do: Integer.floor_div(ts, interval) * interval

  defp aggregate(points, :last) do
    # TODO
  end

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

Output only `aggregate` (with any `@doc`/`@spec`/`@impl` lines that belong
directly above it) — the single function, not the module.
