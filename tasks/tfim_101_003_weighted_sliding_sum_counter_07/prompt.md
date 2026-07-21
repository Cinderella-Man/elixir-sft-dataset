# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule SlidingSum do
  @moduledoc """
  A GenServer that maintains a sliding time-window running **sum of numeric
  amounts** per key, using a sub-bucket strategy.

  Each recorded event carries a numeric amount (bytes transferred, dollars
  spent, points scored, ...). Time is divided into fixed-width sub-buckets of
  `:bucket_ms` milliseconds. Every event is placed into the bucket whose index
  is `div(timestamp, bucket_ms)`, and each bucket accumulates the sum of the
  amounts placed into it.

  When answering `sum/3`, a bucket `b` is included iff its start time falls
  within the sliding window, i.e. `b * bucket_ms >= now - window_ms`. Amounts
  may be integers or floats, and may be negative, so a windowed sum may be
  negative or zero.

  A periodic cleanup (scheduled with `Process.send_after/3`) removes buckets —
  and whole keys — that have fallen outside a reasonable maximum window, so the
  process does not leak memory. A `:cleanup` message may also be sent directly
  to the process to trigger cleanup synchronously (useful for tests).
  """

  use GenServer

  @default_bucket_ms 1_000
  @default_cleanup_interval_ms 60_000

  # Buckets older than this many window-milliseconds are considered expired by
  # the periodic cleanup. It is a generous upper bound on any expected window.
  @max_window_ms 24 * 60 * 60 * 1_000

  @typedoc "A user-supplied key. Any term may be used."
  @type key :: term()

  @typedoc "State held by the server."
  @type state :: %{
          clock: (-> integer()),
          bucket_ms: pos_integer(),
          cleanup_interval_ms: pos_integer() | :infinity,
          keys: %{optional(key()) => %{optional(integer()) => number()}}
        }

  @doc """
  Starts the `SlidingSum` server.

  ## Options

    * `:clock` — a zero-arity function returning the current time in
      milliseconds. Defaults to `fn -> System.monotonic_time(:millisecond) end`.
    * `:bucket_ms` — the width of each internal sub-bucket in milliseconds.
      Defaults to `1_000`.
    * `:name` — optional process registration name.
    * `:cleanup_interval_ms` — how often to run the periodic cleanup. Defaults
      to `60_000`. Pass `:infinity` to disable periodic cleanup.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc """
  Records `amount` for `key` at the current clock time.

  `amount` may be any number: an integer or a float, and it may be negative.
  This call is synchronous so that the amount is guaranteed to be recorded at
  the clock time observed when `add/3` is invoked. Always returns `:ok`.
  """
  @spec add(GenServer.server(), key(), number()) :: :ok
  def add(server, key, amount) when is_number(amount) do
    GenServer.call(server, {:add, key, amount})
  end

  @doc """
  Returns the total of all amounts recorded for `key` that fall within the last
  `window_ms` milliseconds relative to the current clock time.

  Amounts outside the window are not included. A key with no recorded amounts
  returns `0`.
  """
  @spec sum(GenServer.server(), key(), non_neg_integer()) :: number()
  def sum(server, key, window_ms) when is_integer(window_ms) and window_ms >= 0 do
    GenServer.call(server, {:sum, key, window_ms})
  end

  @doc """
  Returns the list of keys currently tracked by the server.

  A key appears only while it still has at least one bucket retained in state.
  After a cleanup removes all of a key's buckets, the key is dropped and will
  not be returned here. Intended for introspection and tests, this lets callers
  observe cleanup behavior through the public API rather than internal state.
  """
  @spec keys(GenServer.server()) :: [key()]
  def keys(server) do
    GenServer.call(server, :keys)
  end

  @impl true
  @spec init(keyword()) :: {:ok, state()}
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    bucket_ms = Keyword.get(opts, :bucket_ms, @default_bucket_ms)
    cleanup_interval_ms = Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms)

    state = %{
      clock: clock,
      bucket_ms: bucket_ms,
      cleanup_interval_ms: cleanup_interval_ms,
      keys: %{}
    }

    {:ok, schedule_cleanup(state)}
  end

  @impl true
  def handle_call({:add, key, amount}, _from, state) do
    now = state.clock.()
    bucket = div(now, state.bucket_ms)

    buckets = Map.get(state.keys, key, %{})
    buckets = Map.update(buckets, bucket, amount, &(&1 + amount))
    keys = Map.put(state.keys, key, buckets)

    {:reply, :ok, %{state | keys: keys}}
  end

  def handle_call({:sum, key, window_ms}, _from, state) do
    now = state.clock.()
    cutoff = now - window_ms

    total =
      state.keys
      |> Map.get(key, %{})
      |> Enum.reduce(0, fn {bucket, bucket_sum}, acc ->
        if bucket * state.bucket_ms >= cutoff, do: acc + bucket_sum, else: acc
      end)

    {:reply, total, state}
  end

  def handle_call(:keys, _from, state) do
    {:reply, Map.keys(state.keys), state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    {:noreply, state |> cleanup() |> schedule_cleanup()}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @spec cleanup(state()) :: state()
  defp cleanup(state) do
    now = state.clock.()
    cutoff = now - @max_window_ms

    keys =
      state.keys
      |> Enum.reduce(%{}, fn {key, buckets}, acc ->
        kept =
          Enum.filter(buckets, fn {bucket, _sum} ->
            bucket * state.bucket_ms >= cutoff
          end)

        if kept == [], do: acc, else: Map.put(acc, key, Map.new(kept))
      end)

    %{state | keys: keys}
  end

  @spec schedule_cleanup(state()) :: state()
  defp schedule_cleanup(%{cleanup_interval_ms: :infinity} = state), do: state

  defp schedule_cleanup(state) do
    Process.send_after(self(), :cleanup, state.cleanup_interval_ms)
    state
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule SlidingSumTest do
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
      SlidingSum.start_link(
        clock: &Clock.now/0,
        bucket_ms: 100,
        cleanup_interval_ms: :infinity
      )

    %{sc: pid}
  end

  test "sum is zero for a key that has had nothing added", %{sc: sc} do
    assert 0 == SlidingSum.sum(sc, "new_key", 1_000)
  end

  test "a single amount is summed within the window", %{sc: sc} do
    SlidingSum.add(sc, "k", 5)
    assert 5 == SlidingSum.sum(sc, "k", 1_000)
  end

  test "multiple amounts are summed within the window", %{sc: sc} do
    SlidingSum.add(sc, "k", 3)
    SlidingSum.add(sc, "k", 4)
    assert 7 == SlidingSum.sum(sc, "k", 1_000)
  end

  test "float amounts are summed", %{sc: sc} do
    SlidingSum.add(sc, "k", 2.5)
    SlidingSum.add(sc, "k", 1.5)
    assert 4.0 == SlidingSum.sum(sc, "k", 1_000)
  end

  test "negative amounts subtract from the running sum", %{sc: sc} do
    SlidingSum.add(sc, "k", 10)
    SlidingSum.add(sc, "k", -3)
    assert 7 == SlidingSum.sum(sc, "k", 1_000)
  end

  test "amounts outside the window are not included", %{sc: sc} do
    # TODO
  end

  test "bucket whose start is within the window is included", %{sc: sc} do
    SlidingSum.add(sc, "k", 5)
    Clock.advance(999)
    assert 5 == SlidingSum.sum(sc, "k", 1_000)
  end

  test "sliding window sums only recent amounts", %{sc: sc} do
    SlidingSum.add(sc, "k", 2)

    Clock.advance(600)
    SlidingSum.add(sc, "k", 5)

    # At t=1050, the amount from t=0 (bucket 0) has slid out; only the 5 remains.
    Clock.advance(450)
    assert 5 == SlidingSum.sum(sc, "k", 1_000)
  end

  test "sum drops to zero once all amounts expire", %{sc: sc} do
    SlidingSum.add(sc, "k", 9)
    Clock.advance(2_000)
    assert 0 == SlidingSum.sum(sc, "k", 1_000)
  end

  test "different keys are completely independent", %{sc: sc} do
    SlidingSum.add(sc, "a", 3)
    SlidingSum.add(sc, "b", 7)

    assert 3 == SlidingSum.sum(sc, "a", 1_000)
    assert 7 == SlidingSum.sum(sc, "b", 1_000)
  end

  test "expired keys are removed during cleanup", %{sc: sc} do
    for i <- 1..50 do
      SlidingSum.add(sc, "key:#{i}", i)
    end

    # Advance past the cleanup's maximum retention window (24 hours) so every
    # bucket is guaranteed to have expired.
    Clock.advance(24 * 60 * 60 * 1_000 + 1_000)
    send(sc, :cleanup)

    # The follow-up call is processed after the :cleanup message, so it acts as
    # a synchronization barrier and observes the post-cleanup key set.
    assert SlidingSum.keys(sc) == []
  end

  test "active keys survive cleanup", %{sc: sc} do
    SlidingSum.add(sc, "active", 42)
    send(sc, :cleanup)

    # The sum/3 call is processed after :cleanup, acting as a barrier, and the
    # active key must still be present.
    assert 42 == SlidingSum.sum(sc, "active", 60_000)
    assert SlidingSum.keys(sc) == ["active"]
  end

  # -------------------------------------------------------
  # Documented defaults and boundaries, observed through the
  # public API (injected clock; sum/3 after send/2 as barrier)
  # -------------------------------------------------------

  test "default bucket_ms is 1000: an amount at t=999 belongs to the bucket at 0", %{sc: _sc} do
    {:ok, sc2} = SlidingSum.start_link(clock: &Clock.now/0, cleanup_interval_ms: :infinity)

    Clock.set(999)
    SlidingSum.add(sc2, "k", 5)
    Clock.set(1_999)

    # Bucket 0 (starting at time 0) lies entirely outside a 1000 ms window now.
    assert 0 == SlidingSum.sum(sc2, "k", 1_000)
  end

  test "default bucket_ms is 1000: an amount at t=1000 starts a new bucket", %{sc: _sc} do
    {:ok, sc2} = SlidingSum.start_link(clock: &Clock.now/0, cleanup_interval_ms: :infinity)

    Clock.set(1_000)
    SlidingSum.add(sc2, "k", 5)

    # Bucket 1 starts exactly at 1000; the cutoff quantizes to bucket starts
    # and the old side is inclusive, so even a 1 ms window still sees it.
    assert 5 == SlidingSum.sum(sc2, "k", 1)
  end

  test "a zero window is legal and follows the inclusive start-time rule", %{sc: sc} do
    SlidingSum.add(sc, "z", 7)

    # window_ms = 0 means cutoff = now; the current bucket starts at 0 = now,
    # which satisfies bucket_start >= now - 0, so the amount is counted.
    assert 7 == SlidingSum.sum(sc, "z", 0)
  end

  test "a bucket starting exactly at the window cutoff is included", %{sc: sc} do
    SlidingSum.add(sc, "edge", 3)
    Clock.set(1_000)

    # cutoff = 1000 - 1000 = 0; the bucket starts at 0 — inclusive boundary.
    assert 3 == SlidingSum.sum(sc, "edge", 1_000)
  end

  test "cleanup keeps a bucket exactly on the 24-hour horizon, drops older ones", %{sc: sc} do
    SlidingSum.add(sc, "old", 5)

    Clock.set(200_000)
    SlidingSum.add(sc, "old", 11)

    # now - 86_400_000 == 0: the t=0 bucket sits exactly on the horizon — kept.
    Clock.set(86_400_000)
    send(sc, :cleanup)
    assert 16 == SlidingSum.sum(sc, "old", 100_000_000)

    # 100 s later the t=0 bucket is beyond the horizon and dropped, while the
    # t=200_000 bucket (start 200_000 >= cutoff 100_000) survives.
    Clock.set(86_500_000)
    send(sc, :cleanup)
    assert 11 == SlidingSum.sum(sc, "old", 100_000_000)
  end

  # -------------------------------------------------------
  # Periodic cleanup: with a real :cleanup_interval_ms the
  # server must run cleanup on its own timer, without any
  # test-sent :cleanup message, and keep doing so afterwards.
  # -------------------------------------------------------

  test "cleanup runs on its own timer and keeps running after each round", %{sc: _sc} do
    {:ok, sc2} =
      SlidingSum.start_link(clock: &Clock.now/0, bucket_ms: 100, cleanup_interval_ms: 25)

    # Round one: a bucket recorded at t=0 is far outside the 24-hour retention
    # horizon once the clock jumps past it, so an unaided cleanup must drop the
    # whole key. Nothing is ever sent to the process here.
    Clock.set(0)
    SlidingSum.add(sc2, "auto", 1)
    assert SlidingSum.keys(sc2) == ["auto"]

    Clock.set(86_400_000 + 100)
    assert wait_until(fn -> SlidingSum.keys(sc2) == [] end, 1_000)

    # Round two: a fresh key recorded after the first automatic run must also be
    # collected, which can only happen if cleanup re-scheduled itself.
    SlidingSum.add(sc2, "auto2", 2)
    assert SlidingSum.keys(sc2) == ["auto2"]

    Clock.set(2 * 86_400_000 + 200)
    assert wait_until(fn -> SlidingSum.keys(sc2) == [] end, 1_000)

    GenServer.stop(sc2)
  end

  # Polls `fun` until it returns true or the deadline passes; returns whether
  # the condition was observed. The deadline is many times the cleanup interval
  # so timing jitter cannot turn a working timer into a failure.
  defp wait_until(fun, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    poll(fun, deadline)
  end

  defp poll(fun, deadline) do
    cond do
      fun.() -> true
      System.monotonic_time(:millisecond) >= deadline -> false
      true -> poll_again(fun, deadline)
    end
  end

  defp poll_again(fun, deadline) do
    Process.sleep(5)
    poll(fun, deadline)
  end
end
```
