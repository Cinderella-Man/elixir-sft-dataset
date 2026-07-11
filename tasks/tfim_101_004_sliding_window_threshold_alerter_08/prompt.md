# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule SlidingAlerter do
  @moduledoc """
  A GenServer that watches a sliding-window event rate per key and reports an
  alarm state when the rate crosses a configured threshold.

  `SlidingAlerter` is a self-clearing threshold detector built on a sub-bucket
  sliding window. Time is divided into fixed-width sub-buckets of `:bucket_ms`
  milliseconds each. Every recorded event is placed into the bucket whose index
  is `div(timestamp, bucket_ms)`. The alerting window spans the most recent
  `:window_ms` milliseconds: a bucket is included in the window's count iff its
  start time `b * bucket_ms` is `>= now - window_ms`.

  A key is in the `:alarm` state when the number of events for that key within
  the window is greater than or equal to `:threshold`; otherwise it is `:ok`.
  The alarm is self-clearing — as events slide out of the window the count
  falls, and once it drops below `:threshold` the status returns to `:ok`
  without any explicit reset.

  A periodic cleanup (scheduled with `Process.send_after/3`) removes buckets —
  and whole keys — whose start time is before `now - window_ms`, so memory does
  not grow without bound.
  """

  use GenServer

  @type key :: term()
  @type status :: :ok | :alarm

  @default_bucket_ms 1_000
  @default_threshold 5
  @default_window_ms 60_000
  @default_cleanup_interval_ms 60_000

  # Public API

  @doc """
  Starts the `SlidingAlerter` process.

  ## Options

    * `:clock` — a zero-arity function returning the current time in
      milliseconds. Defaults to `fn -> System.monotonic_time(:millisecond) end`.
    * `:bucket_ms` — the width of each internal sub-bucket in milliseconds.
      Defaults to `1_000`.
    * `:threshold` — the event count within the window at or above which a key
      is considered to be in alarm. Defaults to `5`.
    * `:window_ms` — the sliding alerting window width in milliseconds.
      Defaults to `60_000`.
    * `:name` — optional process registration name.
    * `:cleanup_interval_ms` — how often to run the periodic cleanup. Defaults
      to `60_000`. Pass `:infinity` to disable.

  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    {name, init_opts} = Keyword.pop(opts, :name)

    case name do
      nil -> GenServer.start_link(__MODULE__, init_opts)
      name -> GenServer.start_link(__MODULE__, init_opts, name: name)
    end
  end

  @doc """
  Records one event for `key` at the current clock time and returns the key's
  resulting status (`:ok` or `:alarm`).
  """
  @spec record(GenServer.server(), key()) :: status()
  def record(server, key) do
    GenServer.call(server, {:record, key})
  end

  @doc """
  Returns `:ok` or `:alarm` for `key` based on the current clock time, without
  recording anything.
  """
  @spec status(GenServer.server(), key()) :: status()
  def status(server, key) do
    GenServer.call(server, {:status, key})
  end

  @doc """
  Returns the number of events recorded for `key` that fall within the last
  `:window_ms` milliseconds relative to the current clock time.
  """
  @spec count(GenServer.server(), key()) :: non_neg_integer()
  def count(server, key) do
    GenServer.call(server, {:count, key})
  end

  # GenServer callbacks

  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)

    state = %{
      clock: clock,
      bucket_ms: Keyword.get(opts, :bucket_ms, @default_bucket_ms),
      threshold: Keyword.get(opts, :threshold, @default_threshold),
      window_ms: Keyword.get(opts, :window_ms, @default_window_ms),
      cleanup_interval_ms: Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms),
      keys: %{}
    }

    schedule_cleanup(state.cleanup_interval_ms)
    {:ok, state}
  end

  @impl true
  def handle_call({:record, key}, _from, state) do
    now = state.clock.()
    bucket = div(now, state.bucket_ms)

    buckets =
      state.keys
      |> Map.get(key, %{})
      |> Map.update(bucket, 1, &(&1 + 1))

    state = %{state | keys: Map.put(state.keys, key, buckets)}
    {:reply, status_for(buckets, now, state), state}
  end

  @impl true
  def handle_call({:status, key}, _from, state) do
    now = state.clock.()
    buckets = Map.get(state.keys, key, %{})
    {:reply, status_for(buckets, now, state), state}
  end

  @impl true
  def handle_call({:count, key}, _from, state) do
    now = state.clock.()
    buckets = Map.get(state.keys, key, %{})
    {:reply, count_for(buckets, now, state), state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    state = cleanup(state)
    schedule_cleanup(state.cleanup_interval_ms)
    {:noreply, state}
  end

  # Internal helpers

  @spec schedule_cleanup(pos_integer() | :infinity) :: :ok
  defp schedule_cleanup(:infinity), do: :ok

  defp schedule_cleanup(interval_ms) when is_integer(interval_ms) do
    Process.send_after(self(), :cleanup, interval_ms)
    :ok
  end

  @spec count_for(map(), integer(), map()) :: non_neg_integer()
  defp count_for(buckets, now, state) do
    cutoff = now - state.window_ms

    Enum.reduce(buckets, 0, fn {bucket, count}, acc ->
      if bucket * state.bucket_ms >= cutoff, do: acc + count, else: acc
    end)
  end

  @spec status_for(map(), integer(), map()) :: status()
  defp status_for(buckets, now, state) do
    if count_for(buckets, now, state) >= state.threshold, do: :alarm, else: :ok
  end

  @spec cleanup(map()) :: map()
  defp cleanup(state) do
    now = state.clock.()
    cutoff = now - state.window_ms

    keys =
      state.keys
      |> Enum.reduce(%{}, fn {key, buckets}, acc ->
        live =
          buckets
          |> Enum.filter(fn {bucket, _count} -> bucket * state.bucket_ms >= cutoff end)
          |> Map.new()

        if map_size(live) == 0, do: acc, else: Map.put(acc, key, live)
      end)

    %{state | keys: keys}
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule SlidingAlerterTest do
  use ExUnit.Case, async: false

  defmodule Clock do
    use Agent

    def start_link(initial \\ 0) do
      Agent.start_link(fn -> initial end, name: __MODULE__)
    end

    def now, do: Agent.get(__MODULE__, & &1)
    def advance(ms), do: Agent.update(__MODULE__, &(&1 + ms))
    def set(ms), do: Agent.update(__MODULE__, fn _ -> ms end)
  end

  setup do
    start_supervised!({Clock, 0})

    {:ok, pid} =
      SlidingAlerter.start_link(
        clock: &Clock.now/0,
        bucket_ms: 100,
        threshold: 3,
        window_ms: 1_000,
        cleanup_interval_ms: :infinity
      )

    %{sc: pid}
  end

  test "unknown key has count zero and status :ok", %{sc: sc} do
    assert 0 = SlidingAlerter.count(sc, "new_key")
    assert :ok = SlidingAlerter.status(sc, "new_key")
  end

  test "below threshold the status stays :ok", %{sc: sc} do
    assert :ok = SlidingAlerter.record(sc, "k")
    assert :ok = SlidingAlerter.record(sc, "k")
    assert :ok = SlidingAlerter.status(sc, "k")
    assert 2 = SlidingAlerter.count(sc, "k")
  end

  test "reaching the threshold puts the key in alarm", %{sc: sc} do
    assert :ok = SlidingAlerter.record(sc, "k")
    assert :ok = SlidingAlerter.record(sc, "k")
    # The third event reaches threshold 3 -> alarm.
    assert :alarm = SlidingAlerter.record(sc, "k")
    assert :alarm = SlidingAlerter.status(sc, "k")
    assert 3 = SlidingAlerter.count(sc, "k")
  end

  test "status stays in alarm while count remains at or above threshold", %{sc: sc} do
    for _ <- 1..3, do: SlidingAlerter.record(sc, "k")
    assert :alarm = SlidingAlerter.record(sc, "k")
    assert 4 = SlidingAlerter.count(sc, "k")
  end

  test "alarm self-clears as events slide out of the window", %{sc: sc} do
    for _ <- 1..3, do: SlidingAlerter.record(sc, "k")
    assert :alarm = SlidingAlerter.status(sc, "k")

    # Advance past the alerting window so all three events expire.
    Clock.advance(1_001)
    assert 0 = SlidingAlerter.count(sc, "k")
    assert :ok = SlidingAlerter.status(sc, "k")
  end

  test "count only includes events within the window", %{sc: sc} do
    SlidingAlerter.record(sc, "k")
    Clock.advance(500)
    SlidingAlerter.record(sc, "k")
    assert 2 = SlidingAlerter.count(sc, "k")

    # Advance so the first event (now 1_100ms old) falls outside the 1_000ms window.
    Clock.advance(600)
    assert 1 = SlidingAlerter.count(sc, "k")
  end

  test "keys are tracked independently", %{sc: sc} do
    # TODO
  end

  test "expired keys are removed during cleanup", %{sc: sc} do
    for i <- 1..50 do
      SlidingAlerter.record(sc, "key:#{i}")
    end

    Clock.advance(10_000)
    send(sc, :cleanup)

    # A subsequent synchronous call is processed after the :cleanup message,
    # so every expired key is observably empty through the public API.
    for i <- 1..50 do
      assert 0 = SlidingAlerter.count(sc, "key:#{i}")
      assert :ok = SlidingAlerter.status(sc, "key:#{i}")
    end
  end

  test "active keys survive cleanup", %{sc: sc} do
    SlidingAlerter.record(sc, "active")
    send(sc, :cleanup)

    # The count call is handled after :cleanup, confirming the live key remains.
    assert 1 = SlidingAlerter.count(sc, "active")
  end
end
```
