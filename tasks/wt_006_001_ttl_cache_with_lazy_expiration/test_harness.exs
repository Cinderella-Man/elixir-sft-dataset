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

    # Verify internal state no longer holds the key
    state = :sys.get_state(cache)
    refute Map.has_key?(state.entries, "k")
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
    for i <- 1..100 do
      TTLCache.put(cache, "key:#{i}", i, 100)
    end

    Clock.advance(200)

    # Trigger sweep manually
    send(cache, :sweep)
    :sys.get_state(cache)

    state = :sys.get_state(cache)
    assert map_size(state.entries) == 0
  end

  test "sweep preserves entries that have not yet expired", %{cache: cache} do
    TTLCache.put(cache, "short", "gone", 100)
    TTLCache.put(cache, "long", "stays", 5_000)

    Clock.advance(200)

    send(cache, :sweep)
    :sys.get_state(cache)

    assert :miss = TTLCache.get(cache, "short")
    assert {:ok, "stays"} = TTLCache.get(cache, "long")

    state = :sys.get_state(cache)
    assert map_size(state.entries) == 1
  end

  test "sweep does not break subsequent put/get operations", %{cache: cache} do
    TTLCache.put(cache, "k", "old", 100)
    Clock.advance(200)

    send(cache, :sweep)
    :sys.get_state(cache)

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
end
