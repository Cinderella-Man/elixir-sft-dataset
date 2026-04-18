defmodule CacheLayerTest do
  use ExUnit.Case, async: false

  # --- Call-count tracker for mocking the fallback ---

  defmodule CallTracker do
    use Agent

    def start_link(return_val) do
      Agent.start_link(fn -> {0, return_val} end, name: __MODULE__)
    end

    def fallback do
      Agent.update(__MODULE__, fn {count, val} -> {count + 1, val} end)
      Agent.get(__MODULE__, fn {_, val} -> val end)
    end

    def call_count, do: Agent.get(__MODULE__, fn {count, _} -> count end)

    def set_return(val),
      do: Agent.update(__MODULE__, fn {count, _} -> {count, val} end)
  end

  setup do
    start_supervised!({CallTracker, :db_value})

    {:ok, pid} = CacheLayer.start_link([])
    %{cl: pid}
  end

  # -------------------------------------------------------
  # Basic fetch behaviour
  # -------------------------------------------------------

  test "cache miss calls fallback and returns value", %{cl: cl} do
    assert {:ok, :db_value} = CacheLayer.fetch(cl, :users, "u:1", &CallTracker.fallback/0)
    assert CallTracker.call_count() == 1
  end

  test "cache hit does not call fallback a second time", %{cl: cl} do
    CacheLayer.fetch(cl, :users, "u:1", &CallTracker.fallback/0)
    assert {:ok, :db_value} = CacheLayer.fetch(cl, :users, "u:1", &CallTracker.fallback/0)
    assert CallTracker.call_count() == 1
  end

  test "fallback return value is correctly stored and returned", %{cl: cl} do
    CallTracker.set_return(%{name: "Alice", age: 30})
    {:ok, first} = CacheLayer.fetch(cl, :users, "u:2", &CallTracker.fallback/0)
    {:ok, second} = CacheLayer.fetch(cl, :users, "u:2", &CallTracker.fallback/0)

    assert first == %{name: "Alice", age: 30}
    assert first == second
    assert CallTracker.call_count() == 1
  end

  # -------------------------------------------------------
  # Invalidate single key
  # -------------------------------------------------------

  test "invalidate removes the key so the next fetch calls fallback again", %{cl: cl} do
    CacheLayer.fetch(cl, :users, "u:1", &CallTracker.fallback/0)
    assert CallTracker.call_count() == 1

    :ok = CacheLayer.invalidate(cl, :users, "u:1")

    CacheLayer.fetch(cl, :users, "u:1", &CallTracker.fallback/0)
    assert CallTracker.call_count() == 2
  end

  test "invalidating a non-existent key returns :ok without error", %{cl: cl} do
    assert :ok = CacheLayer.invalidate(cl, :users, "no-such-key")
  end

  test "invalidate only removes the targeted key, leaving others intact", %{cl: cl} do
    CacheLayer.fetch(cl, :users, "u:1", &CallTracker.fallback/0)
    CacheLayer.fetch(cl, :users, "u:2", &CallTracker.fallback/0)
    assert CallTracker.call_count() == 2

    CacheLayer.invalidate(cl, :users, "u:1")

    # u:2 still cached — no extra fallback call
    CacheLayer.fetch(cl, :users, "u:2", &CallTracker.fallback/0)
    assert CallTracker.call_count() == 2

    # u:1 was evicted — fallback fires again
    CacheLayer.fetch(cl, :users, "u:1", &CallTracker.fallback/0)
    assert CallTracker.call_count() == 3
  end

  # -------------------------------------------------------
  # Invalidate all keys for a table
  # -------------------------------------------------------

  test "invalidate_all clears every key in the table", %{cl: cl} do
    for i <- 1..5 do
      CacheLayer.fetch(cl, :users, "u:#{i}", &CallTracker.fallback/0)
    end

    assert CallTracker.call_count() == 5

    :ok = CacheLayer.invalidate_all(cl, :users)

    for i <- 1..5 do
      CacheLayer.fetch(cl, :users, "u:#{i}", &CallTracker.fallback/0)
    end

    assert CallTracker.call_count() == 10
  end

  test "invalidate_all on an unused table returns :ok without error", %{cl: cl} do
    assert :ok = CacheLayer.invalidate_all(cl, :never_used_table)
  end

  # -------------------------------------------------------
  # Table independence
  # -------------------------------------------------------

  test "different tables are completely independent namespaces", %{cl: cl} do
    CacheLayer.fetch(cl, :users, "id:1", &CallTracker.fallback/0)
    CacheLayer.fetch(cl, :posts, "id:1", &CallTracker.fallback/0)

    # Same key, different tables — two misses
    assert CallTracker.call_count() == 2

    # Both should now be cached independently
    CacheLayer.fetch(cl, :users, "id:1", &CallTracker.fallback/0)
    CacheLayer.fetch(cl, :posts, "id:1", &CallTracker.fallback/0)
    assert CallTracker.call_count() == 2
  end

  test "invalidate_all on one table does not affect another", %{cl: cl} do
    CacheLayer.fetch(cl, :users, "id:1", &CallTracker.fallback/0)
    CacheLayer.fetch(cl, :posts, "id:1", &CallTracker.fallback/0)
    assert CallTracker.call_count() == 2

    CacheLayer.invalidate_all(cl, :users)

    # posts cache untouched
    CacheLayer.fetch(cl, :posts, "id:1", &CallTracker.fallback/0)
    assert CallTracker.call_count() == 2

    # users cache cleared
    CacheLayer.fetch(cl, :users, "id:1", &CallTracker.fallback/0)
    assert CallTracker.call_count() == 3
  end

  # -------------------------------------------------------
  # Lazy table creation
  # -------------------------------------------------------

  test "tables are created on demand and can hold any term as value", %{cl: cl} do
    CallTracker.set_return([1, 2, 3])
    assert {:ok, [1, 2, 3]} = CacheLayer.fetch(cl, :lists, "my_list", &CallTracker.fallback/0)

    CallTracker.set_return(nil)
    # nil is a valid cached value — should NOT trigger a second fallback call
    assert {:ok, nil} = CacheLayer.fetch(cl, :nullables, "k", &CallTracker.fallback/0)
    assert {:ok, nil} = CacheLayer.fetch(cl, :nullables, "k", &CallTracker.fallback/0)
    assert CallTracker.call_count() == 2
  end
end
