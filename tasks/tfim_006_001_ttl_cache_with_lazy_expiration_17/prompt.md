# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule TTLCache do
  @moduledoc """
  A GenServer-based cache that stores key-value pairs with per-key TTL expiration.

  Expiration is enforced lazily on reads and periodically via a background sweep
  to prevent memory leaks from keys that are written but never read again.
  """

  use GenServer

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc "Starts the cache process."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  @doc "Stores `value` under `key` with a TTL of `ttl_ms` milliseconds."
  @spec put(GenServer.server(), term(), term(), non_neg_integer()) :: :ok
  def put(server, key, value, ttl_ms) do
    GenServer.call(server, {:put, key, value, ttl_ms})
  end

  @doc "Retrieves the value for `key`, returning `{:ok, value}` or `:miss`."
  @spec get(GenServer.server(), term()) :: {:ok, term()} | :miss
  def get(server, key) do
    GenServer.call(server, {:get, key})
  end

  @doc "Deletes `key` from the cache. Always returns `:ok`."
  @spec delete(GenServer.server(), term()) :: :ok
  def delete(server, key) do
    GenServer.call(server, {:delete, key})
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @default_sweep_interval_ms 60_000

  defstruct [:clock, :sweep_interval_ms, entries: %{}]

  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    sweep_interval_ms = Keyword.get(opts, :sweep_interval_ms, @default_sweep_interval_ms)

    state = %__MODULE__{
      clock: clock,
      sweep_interval_ms: sweep_interval_ms
    }

    schedule_sweep(sweep_interval_ms)

    {:ok, state}
  end

  @impl true
  def handle_call({:put, key, value, ttl_ms}, _from, state) do
    expires_at = state.clock.() + ttl_ms
    entry = %{value: value, expires_at: expires_at}
    {:reply, :ok, %{state | entries: Map.put(state.entries, key, entry)}}
  end

  def handle_call({:get, key}, _from, state) do
    case Map.fetch(state.entries, key) do
      {:ok, %{value: value, expires_at: expires_at}} ->
        if state.clock.() < expires_at do
          {:reply, {:ok, value}, state}
        else
          {:reply, :miss, %{state | entries: Map.delete(state.entries, key)}}
        end

      :error ->
        {:reply, :miss, state}
    end
  end

  def handle_call({:delete, key}, _from, state) do
    {:reply, :ok, %{state | entries: Map.delete(state.entries, key)}}
  end

  @impl true
  def handle_info(:sweep, state) do
    now = state.clock.()

    pruned =
      state.entries
      |> Enum.reject(fn {_key, %{expires_at: expires_at}} -> now >= expires_at end)
      |> Map.new()

    schedule_sweep(state.sweep_interval_ms)

    {:noreply, %{state | entries: pruned}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Internal helpers
  # ---------------------------------------------------------------------------

  defp schedule_sweep(interval_ms) when is_integer(interval_ms) do
    Process.send_after(self(), :sweep, interval_ms)
  end

  defp schedule_sweep(_), do: :ok
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule TTLCacheTest do
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

    {:ok, pid} =
      TTLCache.start_link(
        clock: &Clock.now/0,
        # disable auto-sweep in tests
        sweep_interval_ms: :infinity
      )

    %{cache: pid}
  end

  # A synchronous read on an unused key: its reply proves the cache has already
  # handled every message sent to it beforehand (such as `:sweep`).
  defp sync(cache) do
    assert :miss = TTLCache.get(cache, "__sync_probe__")
    :ok
  end

  # -------------------------------------------------------
  # Basic put / get
  # -------------------------------------------------------

  test "get returns :miss for a key that was never set", %{cache: cache} do
    assert :miss = TTLCache.get(cache, "nonexistent")
  end

  test "put then get returns the stored value", %{cache: cache} do
    assert :ok = TTLCache.put(cache, "k", "hello", 1_000)
    assert {:ok, "hello"} = TTLCache.get(cache, "k")
  end

  test "put overwrites an existing key", %{cache: cache} do
    TTLCache.put(cache, "k", "v1", 1_000)
    TTLCache.put(cache, "k", "v2", 1_000)
    assert {:ok, "v2"} = TTLCache.get(cache, "k")
  end

  test "stores various Elixir terms as values", %{cache: cache} do
    TTLCache.put(cache, "int", 42, 1_000)
    TTLCache.put(cache, "list", [1, 2, 3], 1_000)
    TTLCache.put(cache, "map", %{a: 1}, 1_000)
    TTLCache.put(cache, "tuple", {:ok, "yes"}, 1_000)

    assert {:ok, 42} = TTLCache.get(cache, "int")
    assert {:ok, [1, 2, 3]} = TTLCache.get(cache, "list")
    assert {:ok, %{a: 1}} = TTLCache.get(cache, "map")
    assert {:ok, {:ok, "yes"}} = TTLCache.get(cache, "tuple")
  end

  # -------------------------------------------------------
  # Lazy expiration on read
  # -------------------------------------------------------

  test "get returns :miss after TTL has elapsed", %{cache: cache} do
    TTLCache.put(cache, "k", "v", 500)
    assert {:ok, "v"} = TTLCache.get(cache, "k")

    Clock.advance(501)
    assert :miss = TTLCache.get(cache, "k")
  end

  test "get returns hit just before TTL expires", %{cache: cache} do
    TTLCache.put(cache, "k", "v", 500)
    Clock.advance(499)
    assert {:ok, "v"} = TTLCache.get(cache, "k")
  end

  test "expired key is removed from internal state on read", %{cache: cache} do
    TTLCache.put(cache, "k", "v", 100)
    Clock.advance(200)

    # Read triggers lazy deletion
    assert :miss = TTLCache.get(cache, "k")

    # Rewinding the clock to well before the expiry cannot resurrect the value:
    # a merely-expired-but-still-stored entry would become readable again, while
    # a lazily deleted one stays a miss forever.
    Clock.set(10)
    assert :miss = TTLCache.get(cache, "k")

    # The key behaves exactly like one that was never written.
    assert :ok = TTLCache.delete(cache, "k")
    assert :miss = TTLCache.get(cache, "k")
  end

  # -------------------------------------------------------
  # TTL reset on overwrite
  # -------------------------------------------------------

  test "put resets the TTL for an existing key", %{cache: cache} do
    TTLCache.put(cache, "k", "v1", 500)
    Clock.advance(400)

    # Overwrite with a fresh TTL of 500 — new expiry is at time 900
    TTLCache.put(cache, "k", "v2", 500)

    # now at time 600 — would have expired under old TTL
    Clock.advance(200)
    assert {:ok, "v2"} = TTLCache.get(cache, "k")

    # now at time 1000 — past new expiry of 900
    Clock.advance(400)
    assert :miss = TTLCache.get(cache, "k")
  end

  # -------------------------------------------------------
  # Delete
  # -------------------------------------------------------

  test "delete removes an existing key", %{cache: cache} do
    TTLCache.put(cache, "k", "v", 1_000)
    assert :ok = TTLCache.delete(cache, "k")
    assert :miss = TTLCache.get(cache, "k")
  end

  test "delete on a nonexistent key returns :ok", %{cache: cache} do
    assert :ok = TTLCache.delete(cache, "ghost")
  end

  test "delete on an already-expired key returns :ok", %{cache: cache} do
    TTLCache.put(cache, "k", "v", 100)
    Clock.advance(200)
    assert :ok = TTLCache.delete(cache, "k")
  end

  # -------------------------------------------------------
  # Key independence
  # -------------------------------------------------------

  test "different keys are completely independent", %{cache: cache} do
    TTLCache.put(cache, "a", "val_a", 300)
    TTLCache.put(cache, "b", "val_b", 1_000)

    Clock.advance(400)

    assert :miss = TTLCache.get(cache, "a")
    assert {:ok, "val_b"} = TTLCache.get(cache, "b")
  end

  test "deleting one key does not affect another", %{cache: cache} do
    TTLCache.put(cache, "a", 1, 1_000)
    TTLCache.put(cache, "b", 2, 1_000)

    TTLCache.delete(cache, "a")

    assert :miss = TTLCache.get(cache, "a")
    assert {:ok, 2} = TTLCache.get(cache, "b")
  end

  # -------------------------------------------------------
  # Edge cases
  # -------------------------------------------------------

  test "very short TTL expires almost immediately", %{cache: cache} do
    TTLCache.put(cache, "k", "v", 1)
    Clock.advance(2)
    assert :miss = TTLCache.get(cache, "k")
  end

  test "very large TTL works correctly", %{cache: cache} do
    TTLCache.put(cache, "k", "v", 86_400_000)
    Clock.advance(86_399_999)
    assert {:ok, "v"} = TTLCache.get(cache, "k")

    Clock.advance(2)
    assert :miss = TTLCache.get(cache, "k")
  end

  # -------------------------------------------------------
  # Periodic sweep (memory leak prevention)
  # -------------------------------------------------------

  test "sweep removes all expired entries from internal state", %{cache: cache} do
    # TODO
  end

  test "sweep preserves entries that have not yet expired", %{cache: cache} do
    TTLCache.put(cache, "short", "gone", 100)
    TTLCache.put(cache, "long", "stays", 5_000)

    Clock.advance(200)

    send(cache, :sweep)
    sync(cache)

    assert :miss = TTLCache.get(cache, "short")
    assert {:ok, "stays"} = TTLCache.get(cache, "long")

    # Back at a time when both entries were live: only "long" survived the sweep,
    # so only "long" can still be read.
    Clock.set(0)
    assert :miss = TTLCache.get(cache, "short")
    assert {:ok, "stays"} = TTLCache.get(cache, "long")
  end

  test "sweep does not break subsequent put/get operations", %{cache: cache} do
    TTLCache.put(cache, "k", "old", 100)
    Clock.advance(200)

    send(cache, :sweep)
    sync(cache)

    TTLCache.put(cache, "k", "new", 1_000)
    assert {:ok, "new"} = TTLCache.get(cache, "k")
  end

  # -------------------------------------------------------
  # Interleaved operations on multiple keys
  # -------------------------------------------------------

  test "interleaved puts, gets, and deletes across keys", %{cache: cache} do
    TTLCache.put(cache, "x", 1, 500)
    TTLCache.put(cache, "y", 2, 1_000)

    Clock.advance(300)
    TTLCache.put(cache, "z", 3, 400)

    assert {:ok, 1} = TTLCache.get(cache, "x")
    assert {:ok, 2} = TTLCache.get(cache, "y")
    assert {:ok, 3} = TTLCache.get(cache, "z")

    # time = 600
    Clock.advance(300)

    # expired at 500
    assert :miss = TTLCache.get(cache, "x")
    # expires at 1000
    assert {:ok, 2} = TTLCache.get(cache, "y")
    # expires at 700
    assert {:ok, 3} = TTLCache.get(cache, "z")

    TTLCache.delete(cache, "y")
    assert :miss = TTLCache.get(cache, "y")
    assert {:ok, 3} = TTLCache.get(cache, "z")

    # time = 800
    Clock.advance(200)
    # expired at 700
    assert :miss = TTLCache.get(cache, "z")
  end

  test "name option registers the process for public API calls" do
    name = :ttl_cache_named_process

    {:ok, _pid} =
      TTLCache.start_link(
        clock: &Clock.now/0,
        sweep_interval_ms: :infinity,
        name: name
      )

    assert :ok = TTLCache.put(name, "k", "v", 1_000)
    assert {:ok, "v"} = TTLCache.get(name, "k")
    assert :ok = TTLCache.delete(name, "k")
    assert :miss = TTLCache.get(name, "k")
  end

  test "put with a shorter TTL retires the previous later expiration", %{cache: cache} do
    TTLCache.put(cache, "k", "v1", 1_000)
    Clock.advance(100)

    # New expiry is 100 + 50 = 150, well before the old expiry of 1_100.
    TTLCache.put(cache, "k", "v2", 50)

    Clock.advance(100)

    # time = 200: past the new expiry (150) even though the old expiry is far away.
    assert :miss = TTLCache.get(cache, "k")
  end

  test "get returns :miss at exactly the TTL boundary", %{cache: cache} do
    TTLCache.put(cache, "k", "v", 500)
    Clock.advance(500)
    assert :miss = TTLCache.get(cache, "k")
  end

  # -------------------------------------------------------
  # Automatic (timer-driven) sweep
  # -------------------------------------------------------

  # Waits for the cache to drop `key` on its own, without the test ever sending
  # a `:sweep` message. The fake clock is parked past the entry's expiration so
  # a timer-driven sweep can discard it, then rewound to a moment when the entry
  # was still live before probing: a still-stored entry reads as a hit there,
  # while a swept one is gone for good. Gives up at a real-time deadline.
  defp await_auto_sweep(cache, key, live_time, expired_time, deadline_ms) do
    deadline = System.monotonic_time(:millisecond) + deadline_ms
    poll_auto_sweep(cache, key, live_time, expired_time, deadline)
  end

  defp poll_auto_sweep(cache, key, live_time, expired_time, deadline) do
    Clock.set(expired_time)

    receive do
    after
      10 -> :ok
    end

    Clock.set(live_time)

    case TTLCache.get(cache, key) do
      :miss ->
        :swept

      {:ok, _value} ->
        if System.monotonic_time(:millisecond) < deadline do
          poll_auto_sweep(cache, key, live_time, expired_time, deadline)
        else
          :still_stored
        end
    end
  end

  test "sweep_interval_ms schedules an automatic sweep that reschedules itself" do
    Clock.set(0)

    {:ok, cache} =
      TTLCache.start_link(
        clock: &Clock.now/0,
        sweep_interval_ms: 25
      )

    # Written at time 0, expires at 100, and is never read while expired — only
    # a timer-driven sweep can remove it.
    assert :ok = TTLCache.put(cache, "first", "v1", 100)
    assert :swept = await_auto_sweep(cache, "first", 50, 1_000, 1_000)

    # A second entry written only after the first automatic sweep already ran is
    # removed as well, which requires the sweep to have rescheduled itself.
    Clock.set(2_000)
    assert :ok = TTLCache.put(cache, "second", "v2", 100)
    assert :swept = await_auto_sweep(cache, "second", 2_050, 3_000, 1_000)

    # Automatic sweeps leave the cache fully usable.
    Clock.set(4_000)
    assert :ok = TTLCache.put(cache, "third", "v3", 60_000)
    assert {:ok, "v3"} = TTLCache.get(cache, "third")
  end
end
```
