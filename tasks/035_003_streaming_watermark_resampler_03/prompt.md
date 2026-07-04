Implement the `handle_call/3` GenServer callback for `StreamingResampler`. It handles four
kinds of synchronous messages, and every clause must return a standard `{:reply, reply, state}`
tuple.

- `{:push, ts, value}` — ingest one data point. First make sure the emission grid has been
  started for this timestamp using `ensure_started/2` (the first point ever pushed fixes the
  grid origin). Then advance the watermark to `bump(state.watermark, ts)`. Compute the point's
  bucket with `floor_bucket(ts, state.interval)`. If that bucket is earlier than
  `state.next_emit` (i.e. its bucket has already been emitted) the point is a *late drop*:
  increment `state.late_dropped` and otherwise leave the state unchanged. Otherwise append the
  `{ts, value}` point to the list of points buffered for that bucket in `state.open` (prepend
  is fine — buckets are sorted by timestamp at finalization). Finally run `finalize/1` on the
  resulting state to emit any buckets the new watermark has made finalizable, and reply `:ok`.

- `:finalized` — reply with the buckets finalized so far. They are stored newest-first in
  `state.emitted`, so reply with `Enum.reverse(state.emitted)`. The state is unchanged.

- `:flush` — force-finalize every still-open bucket up to and including the bucket containing
  the current watermark by calling `flush_all/1`, then reply with `Enum.reverse(state.emitted)`
  of the resulting state (and keep that resulting state).

- `:stats` — reply with a map containing `:late_dropped` (from `state.late_dropped`),
  `:watermark` (from `state.watermark`), and `:open_buckets` (`map_size(state.open)`). The
  state is unchanged.

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

  @valid_agg  [:last, :first, :mean, :sum, :count, :max, :min]
  @valid_fill [:nil, :forward]

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
    _ = fetch_opt!(opts, :fill, :nil, @valid_fill)

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
      fill: fetch_opt!(opts, :fill, :nil, @valid_fill),
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
    # TODO
  end

  def handle_call(:finalized, _from, state) do
    # TODO
  end

  def handle_call(:flush, _from, state) do
    # TODO
  end

  def handle_call(:stats, _from, state) do
    # TODO
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
        :error        -> nil
      end

    filled =
      case {agg_value, state.fill} do
        {nil, :forward} -> state.last_value
        {nil, :nil}     -> nil
        {v, _}          -> v
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

  defp floor_bucket(ts, interval), do: div(ts, interval) * interval

  defp aggregate(points, :last),  do: points |> List.last() |> elem(1)
  defp aggregate(points, :first), do: points |> hd() |> elem(1)
  defp aggregate(points, :count), do: length(points)
  defp aggregate(points, :sum),   do: Enum.reduce(points, 0, fn {_t, v}, acc -> acc + v end)
  defp aggregate(points, :max),   do: points |> Enum.map(&elem(&1, 1)) |> Enum.max()
  defp aggregate(points, :min),   do: points |> Enum.map(&elem(&1, 1)) |> Enum.min()

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