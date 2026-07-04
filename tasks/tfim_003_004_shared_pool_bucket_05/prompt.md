# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule SharedPoolBucket do
  @moduledoc """
  A GenServer implementing two-level token-based rate limiting.

  Each call passes through two independent token buckets:

    1. A **per-key bucket**, whose capacity and refill rate are specified per
       call (like the original leaky bucket task).
    2. A **global pool** shared across all keys, whose capacity and refill
       rate are configured once at `start_link/1`.

  An acquire succeeds only when both levels have enough tokens.  If the
  per-key bucket is short, return `:key_empty`; if per-key has enough but
  the global pool is short, return `:global_empty`.  On rejection, **nothing
  is drained from either level** — both levels are returned to their pre-
  evaluation state (which, after the lazy refill, reflects the current time).

  Per-key state:

      %{free, capacity, refill_rate, last_update_at}

  Global state, stored at the top level (NOT in the buckets map):

      global_free :: float
      global_capacity :: pos_integer
      global_refill_rate :: float
      global_last_update_at :: integer

  ## Options

    * `:global_capacity`      – required, max tokens in the shared pool
    * `:global_refill_rate`   – required, shared-pool refill tokens/sec
    * `:name`                 – optional process registration
    * `:clock`                – `(-> integer())` current time in ms
    * `:cleanup_interval_ms`  – periodic sweep interval (default 60_000)

  """

  use GenServer

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    _ = Keyword.fetch!(opts, :global_capacity)
    _ = Keyword.fetch!(opts, :global_refill_rate)

    {name, opts} = Keyword.pop(opts, :name)

    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  @doc """
  Attempts to atomically drain `tokens` from both the per-key bucket and the
  shared global pool.

  Returns `{:ok, key_remaining, global_remaining}` on success, or
  `{:error, :key_empty | :global_empty, retry_after_ms}` on rejection.
  `:key_empty` takes precedence when both levels would fail.
  """
  @spec acquire(GenServer.server(), term(), pos_integer(), number(), pos_integer()) ::
          {:ok, non_neg_integer(), non_neg_integer()}
          | {:error, :key_empty | :global_empty, pos_integer()}
  def acquire(server, bucket_name, key_capacity, key_refill_rate, tokens \\ 1)
      when is_integer(key_capacity) and key_capacity > 0 and
           is_number(key_refill_rate) and key_refill_rate > 0 and
           is_integer(tokens) and tokens > 0 do
    GenServer.call(
      server,
      {:acquire, bucket_name, key_capacity, key_refill_rate * 1.0, tokens}
    )
  end

  @doc "Returns the current global pool balance (floor of float)."
  @spec global_level(GenServer.server()) :: {:ok, non_neg_integer()}
  def global_level(server), do: GenServer.call(server, :global_level)

  @doc """
  Returns the current per-key bucket balance (floor of float), or
  `{:ok, key_capacity}` if the bucket has never been seen.
  """
  @spec key_level(GenServer.server(), term(), pos_integer(), number()) ::
          {:ok, non_neg_integer()}
  def key_level(server, bucket_name, key_capacity, key_refill_rate)
      when is_integer(key_capacity) and key_capacity > 0 and
           is_number(key_refill_rate) and key_refill_rate > 0 do
    GenServer.call(
      server,
      {:key_level, bucket_name, key_capacity, key_refill_rate * 1.0}
    )
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @default_cleanup_interval_ms 60_000

  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    cleanup_interval = Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms)

    global_capacity = Keyword.fetch!(opts, :global_capacity)
    global_refill_rate = Keyword.fetch!(opts, :global_refill_rate) * 1.0

    now = clock.()
    schedule_cleanup(cleanup_interval)

    {:ok,
     %{
       buckets: %{},
       clock: clock,
       cleanup_interval_ms: cleanup_interval,
       # Global pool — lives at top level, not in buckets map.
       global_free: global_capacity * 1.0,
       global_capacity: global_capacity,
       global_refill_rate: global_refill_rate,
       global_last_update_at: now
     }}
  end

  @impl true
  def handle_call({:acquire, name, key_cap, key_rate, tokens}, _from, state) do
    now = state.clock.()

    # Apply lazy refill to both levels BEFORE evaluating the drain.
    state = refill_global(state, now)
    {bucket, state} = get_and_refill_bucket(state, name, key_cap, key_rate, now)

    cond do
      bucket.free < tokens ->
        # Per-key is the blocker — signal :key_empty even if global is also short.
        deficit = tokens - bucket.free
        retry_after = ceil_positive(deficit * 1000 / key_rate)

        # Persist the refilled bucket state (no drain) so the refill clock
        # is up to date next time.
        new_buckets = Map.put(state.buckets, name, bucket)
        {:reply, {:error, :key_empty, retry_after}, %{state | buckets: new_buckets}}

      state.global_free < tokens ->
        # Per-key would have permitted, global is the blocker.
        deficit = tokens - state.global_free
        retry_after = ceil_positive(deficit * 1000 / state.global_refill_rate)

        new_buckets = Map.put(state.buckets, name, bucket)
        {:reply, {:error, :global_empty, retry_after}, %{state | buckets: new_buckets}}

      true ->
        # Drain both levels atomically.
        new_bucket = %{bucket | free: bucket.free - tokens}
        new_buckets = Map.put(state.buckets, name, new_bucket)
        new_global = state.global_free - tokens

        {:reply, {:ok, trunc(new_bucket.free), trunc(new_global)},
         %{state | buckets: new_buckets, global_free: new_global}}
    end
  end

  def handle_call(:global_level, _from, state) do
    state = refill_global(state, state.clock.())
    {:reply, {:ok, trunc(state.global_free)}, state}
  end

  def handle_call({:key_level, name, key_cap, key_rate}, _from, state) do
    case Map.fetch(state.buckets, name) do
      :error ->
        # Never seen — fresh buckets are full.
        {:reply, {:ok, key_cap}, state}

      {:ok, _} ->
        now = state.clock.()
        {bucket, state} = get_and_refill_bucket(state, name, key_cap, key_rate, now)
        new_buckets = Map.put(state.buckets, name, bucket)
        {:reply, {:ok, trunc(bucket.free)}, %{state | buckets: new_buckets}}
    end
  end

  @impl true
  def handle_info(:cleanup, state) do
    now = state.clock.()

    # Keep global refill up-to-date on cleanup too.
    state = refill_global(state, now)

    cleaned =
      Enum.reduce(state.buckets, %{}, fn {name, bucket}, acc ->
        elapsed = now - bucket.last_update_at
        projected = min(bucket.capacity * 1.0, bucket.free + elapsed * bucket.refill_rate / 1000)

        # Bucket indistinguishable from a fresh one — safe to drop.
        if projected >= bucket.capacity do
          acc
        else
          Map.put(acc, name, %{bucket | free: projected, last_update_at: now})
        end
      end)

    schedule_cleanup(state.cleanup_interval_ms)
    {:noreply, %{state | buckets: cleaned}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Per-level refill helpers
  # ---------------------------------------------------------------------------

  defp refill_global(state, now) do
    elapsed = now - state.global_last_update_at
    added = elapsed * state.global_refill_rate / 1000
    new_free = min(state.global_capacity * 1.0, state.global_free + added)
    %{state | global_free: new_free, global_last_update_at: now}
  end

  defp get_and_refill_bucket(state, name, key_cap, key_rate, now) do
    bucket =
      case Map.fetch(state.buckets, name) do
        {:ok, existing} ->
          # Allow capacity/rate to be updated mid-stream.
          %{existing | capacity: key_cap, refill_rate: key_rate}

        :error ->
          %{
            free: key_cap * 1.0,
            capacity: key_cap,
            refill_rate: key_rate,
            last_update_at: now
          }
      end

    elapsed = now - bucket.last_update_at
    added = elapsed * bucket.refill_rate / 1000
    new_free = min(bucket.capacity * 1.0, bucket.free + added)

    {%{bucket | free: new_free, last_update_at: now}, state}
  end

  # ---------------------------------------------------------------------------
  # Misc
  # ---------------------------------------------------------------------------

  defp ceil_positive(x) when is_number(x) do
    c = trunc(x)
    c = if c < x, do: c + 1, else: c
    max(c, 1)
  end

  defp schedule_cleanup(:infinity), do: :ok

  defp schedule_cleanup(interval_ms) when is_integer(interval_ms) do
    Process.send_after(self(), :cleanup, interval_ms)
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule SharedPoolBucketTest do
  use ExUnit.Case, async: false

  # --- Fake clock for deterministic testing ---

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

    # Global pool: 10 capacity, 1 token/sec refill
    {:ok, pid} =
      SharedPoolBucket.start_link(
        global_capacity: 10,
        global_refill_rate: 1.0,
        clock: &Clock.now/0,
        cleanup_interval_ms: :infinity
      )

    %{sp: pid}
  end

  # -------------------------------------------------------
  # Happy path
  # -------------------------------------------------------

  test "both levels drain on a successful acquire", %{sp: sp} do
    # Per-key: 5 capacity, 0.5/sec. Global: 10 capacity, 1/sec.
    assert {:ok, 4, 9} = SharedPoolBucket.acquire(sp, "alice", 5, 0.5)
    assert {:ok, 3, 8} = SharedPoolBucket.acquire(sp, "alice", 5, 0.5)
  end

  test "global pool drains across different keys", %{sp: sp} do
    # Alice takes 3, Bob takes 3 — each has their own per-key budget,
    # but the global pool should be at 10 - 3 - 3 = 4
    SharedPoolBucket.acquire(sp, "alice", 5, 1.0, 3)
    SharedPoolBucket.acquire(sp, "bob", 5, 1.0, 3)

    assert {:ok, 4} = SharedPoolBucket.global_level(sp)
  end

  # -------------------------------------------------------
  # Per-key exhaustion
  # -------------------------------------------------------

  test "per-key exhaustion returns :key_empty", %{sp: sp} do
    # Alice drains her per-key (capacity 3, small relative to global 10)
    for _ <- 1..3, do: SharedPoolBucket.acquire(sp, "alice", 3, 1.0)

    assert {:error, :key_empty, retry_after} =
             SharedPoolBucket.acquire(sp, "alice", 3, 1.0)

    assert is_integer(retry_after)
    assert retry_after > 0

    # Bob is unaffected — global pool still has 7
    assert {:ok, 2, 6} = SharedPoolBucket.acquire(sp, "bob", 3, 1.0)
  end

  test "rejected acquire does not drain either level", %{sp: sp} do
    # TODO
  end

  # -------------------------------------------------------
  # Global exhaustion
  # -------------------------------------------------------

  test "global exhaustion returns :global_empty when per-key has capacity", %{sp: sp} do
    # Drain global pool using multiple clients, each with a large per-key cap
    SharedPoolBucket.acquire(sp, "alice", 20, 1.0, 5)
    SharedPoolBucket.acquire(sp, "bob", 20, 1.0, 5)

    # Global pool now at 0, but a new client "carol" with capacity 20 has a full per-key bucket
    assert {:ok, 0} = SharedPoolBucket.global_level(sp)
    assert {:ok, 20} = SharedPoolBucket.key_level(sp, "carol", 20, 1.0)

    assert {:error, :global_empty, retry_after} =
             SharedPoolBucket.acquire(sp, "carol", 20, 1.0)

    assert is_integer(retry_after)
    assert retry_after > 0

    # Rejected → Carol's per-key bucket wasn't drained
    assert {:ok, 20} = SharedPoolBucket.key_level(sp, "carol", 20, 1.0)
  end

  # -------------------------------------------------------
  # Priority: :key_empty takes precedence when both levels are short
  # -------------------------------------------------------

  test "both-empty precedence: per-key reported even when global also empty" do
    # Removed the redundant `start_supervised!({Clock, 0})` here

    {:ok, sp} =
      SharedPoolBucket.start_link(
        global_capacity: 2,
        global_refill_rate: 1.0,
        clock: &Clock.now/0,
        cleanup_interval_ms: :infinity
      )

    # Drain both sides simultaneously — alice's 2-token bucket AND the 2-token global
    SharedPoolBucket.acquire(sp, "alice", 2, 1.0)
    SharedPoolBucket.acquire(sp, "alice", 2, 1.0)

    # Now alice-free = 0 AND global-free = 0.
    assert {:ok, 0} = SharedPoolBucket.key_level(sp, "alice", 2, 1.0)
    assert {:ok, 0} = SharedPoolBucket.global_level(sp)

    # Both levels short — must report :key_empty, not :global_empty.
    assert {:error, :key_empty, _} = SharedPoolBucket.acquire(sp, "alice", 2, 1.0)
  end

  # -------------------------------------------------------
  # Refill on both levels
  # -------------------------------------------------------

  test "both levels refill lazily on subsequent calls", %{sp: sp} do
    # Drain alice's per-key (capacity 3, refill 1/sec)
    for _ <- 1..3, do: SharedPoolBucket.acquire(sp, "alice", 3, 1.0)
    # Drain some of global
    for _ <- 1..3, do: SharedPoolBucket.acquire(sp, "bob", 5, 2.0)

    # Global is now at 4, alice-per-key is at 0
    assert {:ok, 4} = SharedPoolBucket.global_level(sp)

    # Advance 3 seconds.  Per-key refills at 1/sec → +3 tokens → full at 3.
    # Global refills at 1/sec → +3 tokens → up to 7.
    Clock.advance(3_000)

    assert {:ok, 3} = SharedPoolBucket.key_level(sp, "alice", 3, 1.0)
    assert {:ok, 7} = SharedPoolBucket.global_level(sp)
  end

  test "per-key refill caps at per-key capacity", %{sp: sp} do
    # Drain alice (cap 2)
    SharedPoolBucket.acquire(sp, "alice", 2, 1.0)
    SharedPoolBucket.acquire(sp, "alice", 2, 1.0)

    # Idle a very long time — alice must cap at 2, not overflow
    Clock.advance(1_000_000)

    assert {:ok, 2} = SharedPoolBucket.key_level(sp, "alice", 2, 1.0)
  end

  test "global refill caps at global capacity", %{sp: sp} do
    # Drain global partially
    for _ <- 1..5, do: SharedPoolBucket.acquire(sp, "alice", 10, 10.0)

    # Idle a very long time — global caps at 10
    Clock.advance(1_000_000)

    assert {:ok, 10} = SharedPoolBucket.global_level(sp)
  end

  # -------------------------------------------------------
  # Multi-token acquires
  # -------------------------------------------------------

  test "multi-token drain math is correct" do
    # Removed the redundant `start_supervised!({Clock, 0})` here

    {:ok, sp} =
      SharedPoolBucket.start_link(
        global_capacity: 10,
        global_refill_rate: 1.0,
        clock: &Clock.now/0,
        cleanup_interval_ms: :infinity
      )

    assert {:ok, 2, 7} = SharedPoolBucket.acquire(sp, "alice", 5, 1.0, 3)
    assert {:ok, 0, 5} = SharedPoolBucket.acquire(sp, "alice", 5, 1.0, 2)
  end

  # -------------------------------------------------------
  # key_level for unknown buckets
  # -------------------------------------------------------

  test "key_level for unknown bucket returns capacity", %{sp: sp} do
    assert {:ok, 7} = SharedPoolBucket.key_level(sp, "never_seen", 7, 1.0)
    # Must not have created the bucket
    state = :sys.get_state(sp)
    refute Map.has_key?(state.buckets, "never_seen")
  end

  # -------------------------------------------------------
  # Cleanup
  # -------------------------------------------------------

  test "refilled buckets are dropped in cleanup; global is kept", %{sp: sp} do
    # Touch 50 buckets
    for i <- 1..50, do: SharedPoolBucket.acquire(sp, "k:#{i}", 2, 5.0)

    # Advance long enough for per-key buckets to fully refill
    Clock.advance(10_000)

    send(sp, :cleanup)
    :sys.get_state(sp)

    state = :sys.get_state(sp)
    assert map_size(state.buckets) == 0

    # Global pool is still present — and should have refilled to capacity
    assert {:ok, 10} = SharedPoolBucket.global_level(sp)
  end
end
```
