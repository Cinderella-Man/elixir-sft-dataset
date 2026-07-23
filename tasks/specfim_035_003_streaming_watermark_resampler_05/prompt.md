# Reconstruct the missing typespec

In the otherwise-complete module below, the `@spec` for
`flush/1` has been removed; `# TODO: @spec` holds its place.
Write that one attribute — a `@spec` for `flush/1` faithful to
the arguments, guards, and every return shape the code can actually
produce. Nothing else changes.

## The module with the `@spec` for `flush/1` missing

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
  # TODO: @spec
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

  defp aggregate(points, :last), do: points |> List.last() |> elem(1)
  defp aggregate(points, :first), do: points |> hd() |> elem(1)
  defp aggregate(points, :count), do: length(points)
  defp aggregate(points, :sum), do: Enum.reduce(points, 0, fn {_t, v}, acc -> acc + v end)
  defp aggregate(points, :max), do: points |> Enum.map(&elem(&1, 1)) |> Enum.max()
  defp aggregate(points, :min), do: points |> Enum.map(&elem(&1, 1)) |> Enum.min()

  defp aggregate(points, :mean) do
    {sum, count} =
      Enum.reduce(points, {0, 0}, fn {_t, v}, {s, c} -> {s + v, c + 1} end)

    sum / count
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

Reply with the `@spec` attribute alone, however many lines it needs —
not the module.
