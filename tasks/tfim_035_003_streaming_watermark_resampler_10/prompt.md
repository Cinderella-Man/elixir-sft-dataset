# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

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

  defp floor_bucket(ts, interval), do: div(ts, interval) * interval

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

## Test harness — implement the `# TODO` test

```elixir
defmodule StreamingResamplerTest do
  use ExUnit.Case, async: false

  test "buckets finalize as the watermark advances (lateness 0)" do
    {:ok, pid} = StreamingResampler.start_link(1_000, agg: :sum)

    :ok = StreamingResampler.push(pid, 0, 5)
    :ok = StreamingResampler.push(pid, 200, 5)
    # watermark 200 -> bucket [0,1000) not yet closed
    assert StreamingResampler.finalized(pid) == []

    :ok = StreamingResampler.push(pid, 1_500, 10)
    # watermark 1500 -> bucket 0 closes with sum 10
    assert StreamingResampler.finalized(pid) == [{0, 10}]

    :ok = StreamingResampler.push(pid, 2_500, 20)
    # watermark 2500 -> bucket 1000 closes with sum 10
    assert StreamingResampler.finalized(pid) == [{0, 10}, {1_000, 10}]
  end

  test "flush finalizes the remaining open buckets" do
    {:ok, pid} = StreamingResampler.start_link(1_000, agg: :sum)

    Enum.each([{0, 5}, {200, 5}, {1_500, 10}, {2_500, 20}], fn {t, v} ->
      StreamingResampler.push(pid, t, v)
    end)

    assert StreamingResampler.flush(pid) == [{0, 10}, {1_000, 10}, {2_000, 20}]
  end

  test "late points into an already-finalized bucket are dropped and counted" do
    {:ok, pid} = StreamingResampler.start_link(1_000, agg: :sum)

    StreamingResampler.push(pid, 0, 5)
    StreamingResampler.push(pid, 1_500, 10)
    # bucket 0 is now finalized (next awaiting emission is 1000)
    assert StreamingResampler.finalized(pid) == [{0, 5}]

    :ok = StreamingResampler.push(pid, 300, 99)
    assert StreamingResampler.finalized(pid) == [{0, 5}]
    assert StreamingResampler.stats(pid).late_dropped == 1
  end

  test "allowed_lateness keeps a bucket open for late arrivals" do
    {:ok, pid} = StreamingResampler.start_link(1_000, agg: :sum, allowed_lateness: 500)

    StreamingResampler.push(pid, 0, 5)
    StreamingResampler.push(pid, 1_200, 10)
    # bucket 0 needs watermark >= 1000 + 500 = 1500 to close; wm is 1200 -> still open
    assert StreamingResampler.finalized(pid) == []

    :ok = StreamingResampler.push(pid, 300, 7)
    assert StreamingResampler.stats(pid).late_dropped == 0

    StreamingResampler.push(pid, 1_800, 3)
    # now wm 1800 >= 1500 -> bucket 0 closes including the late 7
    assert StreamingResampler.finalized(pid) == [{0, 12}]
  end

  test "empty buckets in the middle are emitted contiguously (fill :nil)" do
    {:ok, pid} = StreamingResampler.start_link(1_000, agg: :sum, fill: nil)

    StreamingResampler.push(pid, 0, 5)
    StreamingResampler.push(pid, 3_200, 9)

    assert StreamingResampler.finalized(pid) == [{0, 5}, {1_000, nil}, {2_000, nil}]
  end

  test "fill :forward carries the last aggregate into empty buckets" do
    {:ok, pid} = StreamingResampler.start_link(1_000, agg: :sum, fill: :forward)

    StreamingResampler.push(pid, 0, 5)
    StreamingResampler.push(pid, 3_200, 9)

    assert StreamingResampler.finalized(pid) == [{0, 5}, {1_000, 5}, {2_000, 5}]
  end

  test ":last respects timestamp order even for out-of-order arrivals" do
    {:ok, pid} = StreamingResampler.start_link(1_000, agg: :last, allowed_lateness: 1_000)

    StreamingResampler.push(pid, 100, 1)
    StreamingResampler.push(pid, 900, 2)
    StreamingResampler.push(pid, 500, 3)
    StreamingResampler.flush(pid)

    # within bucket 0 the latest timestamp is 900 -> value 2
    assert StreamingResampler.finalized(pid) == [{0, 2}]
  end

  test "stats reports watermark and open bucket count" do
    {:ok, pid} = StreamingResampler.start_link(1_000, agg: :sum)

    StreamingResampler.push(pid, 0, 5)
    StreamingResampler.push(pid, 1_200, 7)

    stats = StreamingResampler.stats(pid)
    assert stats.watermark == 1_200
    # bucket 0 closed, bucket 1000 open
    assert stats.open_buckets == 1
  end

  test "finalized/flush/stats before any push" do
    # TODO
  end

  test "points after flush that map to emitted buckets are late drops" do
    {:ok, pid} = StreamingResampler.start_link(1_000, agg: :sum)

    StreamingResampler.push(pid, 0, 5)
    StreamingResampler.push(pid, 900, 5)
    StreamingResampler.flush(pid)

    :ok = StreamingResampler.push(pid, 100, 99)
    assert StreamingResampler.stats(pid).late_dropped == 1
    assert StreamingResampler.finalized(pid) == [{0, 10}]
  end

  test "invalid interval and options raise ArgumentError" do
    assert_raise ArgumentError, fn -> StreamingResampler.start_link(0) end
    assert_raise ArgumentError, fn -> StreamingResampler.start_link(1_000, agg: :median) end

    assert_raise ArgumentError, fn ->
      StreamingResampler.start_link(1_000, allowed_lateness: -1)
    end
  end
end
```
