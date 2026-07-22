defmodule LRUCacheTest do
  use ExUnit.Case, async: false

  # Helper: start a uniquely named cache per test to avoid collisions
  defp start_cache(max_size) do
    name = :"lru_#{System.unique_integer([:positive])}"
    start_supervised!({LRUCache, name: name, max_size: max_size})
    name
  end

  # -------------------------------------------------------
  # Basic get / put
  # -------------------------------------------------------

  test "get returns :miss for unknown key" do
    c = start_cache(3)
    assert :miss = LRUCache.get(c, :missing)
  end

  test "put and get round-trip" do
    c = start_cache(3)
    assert :ok = LRUCache.put(c, :a, 1)
    assert {:ok, 1} = LRUCache.get(c, :a)
  end

  test "put overwrites an existing key" do
    c = start_cache(3)
    LRUCache.put(c, :a, 1)
    LRUCache.put(c, :a, 42)
    assert {:ok, 42} = LRUCache.get(c, :a)
  end

  test "multiple distinct keys coexist" do
    c = start_cache(5)
    for i <- 1..5, do: LRUCache.put(c, i, i * 10)

    for i <- 1..5 do
      expected = i * 10
      assert {:ok, ^expected} = LRUCache.get(c, i)
    end
  end

  # -------------------------------------------------------
  # Eviction — basic LRU order
  # -------------------------------------------------------

  test "oldest entry is evicted when cache exceeds max_size" do
    c = start_cache(3)
    # inserted first → LRU
    LRUCache.put(c, :a, 1)
    LRUCache.put(c, :b, 2)
    LRUCache.put(c, :c, 3)
    # should evict :a
    LRUCache.put(c, :d, 4)

    assert :miss = LRUCache.get(c, :a)
    assert {:ok, 2} = LRUCache.get(c, :b)
    assert {:ok, 3} = LRUCache.get(c, :c)
    assert {:ok, 4} = LRUCache.get(c, :d)
  end

  test "filling beyond capacity evicts in insertion order" do
    c = start_cache(2)
    LRUCache.put(c, :x, 10)
    LRUCache.put(c, :y, 20)
    # evicts :x
    LRUCache.put(c, :z, 30)
    # evicts :y
    LRUCache.put(c, :w, 40)

    assert :miss = LRUCache.get(c, :x)
    assert :miss = LRUCache.get(c, :y)
    assert {:ok, 30} = LRUCache.get(c, :z)
    assert {:ok, 40} = LRUCache.get(c, :w)
  end

  # -------------------------------------------------------
  # get refreshes recency — prevents premature eviction
  # -------------------------------------------------------

  test "get saves an entry from eviction" do
    c = start_cache(3)
    LRUCache.put(c, :a, 1)
    LRUCache.put(c, :b, 2)
    LRUCache.put(c, :c, 3)

    # Touch :a so it becomes MRU; :b is now the LRU
    LRUCache.get(c, :a)

    # Adding :d should evict :b, not :a
    LRUCache.put(c, :d, 4)

    assert {:ok, 1} = LRUCache.get(c, :a)
    assert :miss = LRUCache.get(c, :b)
    assert {:ok, 3} = LRUCache.get(c, :c)
    assert {:ok, 4} = LRUCache.get(c, :d)
  end

  test "repeated gets keep pushing an entry to MRU position" do
    c = start_cache(3)
    LRUCache.put(c, :a, 1)
    LRUCache.put(c, :b, 2)
    LRUCache.put(c, :c, 3)

    # Keep touching :a
    LRUCache.get(c, :a)
    LRUCache.get(c, :a)

    # evicts :b (oldest untouched)
    LRUCache.put(c, :d, 4)
    # evicts :c
    LRUCache.put(c, :e, 5)

    assert {:ok, 1} = LRUCache.get(c, :a)
    assert :miss = LRUCache.get(c, :b)
    assert :miss = LRUCache.get(c, :c)
    assert {:ok, 4} = LRUCache.get(c, :d)
    assert {:ok, 5} = LRUCache.get(c, :e)
  end

  # -------------------------------------------------------
  # put on existing key refreshes recency
  # -------------------------------------------------------

  test "updating an existing key refreshes its recency" do
    c = start_cache(3)
    LRUCache.put(c, :a, 1)
    LRUCache.put(c, :b, 2)
    LRUCache.put(c, :c, 3)

    # Update :a — it should now be MRU; :b becomes LRU
    LRUCache.put(c, :a, 99)

    # should evict :b
    LRUCache.put(c, :d, 4)

    assert {:ok, 99} = LRUCache.get(c, :a)
    assert :miss = LRUCache.get(c, :b)
    assert {:ok, 3} = LRUCache.get(c, :c)
    assert {:ok, 4} = LRUCache.get(c, :d)
  end

  # -------------------------------------------------------
  # Max size of 1 — extreme edge case
  # -------------------------------------------------------

  test "cache of size 1 always holds only the latest entry" do
    c = start_cache(1)
    LRUCache.put(c, :a, 1)
    LRUCache.put(c, :b, 2)

    assert :miss = LRUCache.get(c, :a)
    assert {:ok, 2} = LRUCache.get(c, :b)

    LRUCache.put(c, :c, 3)

    assert :miss = LRUCache.get(c, :b)
    assert {:ok, 3} = LRUCache.get(c, :c)
  end

  test "get on the sole entry in a size-1 cache still returns it" do
    c = start_cache(1)
    LRUCache.put(c, :only, :value)
    assert {:ok, :value} = LRUCache.get(c, :only)
    assert {:ok, :value} = LRUCache.get(c, :only)
  end

  # -------------------------------------------------------
  # Values: arbitrary terms
  # -------------------------------------------------------

  test "cache stores arbitrary Elixir terms as values" do
    c = start_cache(5)
    LRUCache.put(c, :list, [1, 2, 3])
    LRUCache.put(c, :map, %{a: 1})
    LRUCache.put(c, :tuple, {:ok, "hello"})
    LRUCache.put(c, nil, nil)

    assert {:ok, [1, 2, 3]} = LRUCache.get(c, :list)
    assert {:ok, %{a: 1}} = LRUCache.get(c, :map)
    assert {:ok, {:ok, "hello"}} = LRUCache.get(c, :tuple)
    assert {:ok, nil} = LRUCache.get(c, nil)
  end

  # -------------------------------------------------------
  # Multiple independent cache instances
  # -------------------------------------------------------

  test "two cache instances are fully independent" do
    c1 = start_cache(2)
    c2 = start_cache(2)

    LRUCache.put(c1, :a, :from_c1)
    LRUCache.put(c2, :a, :from_c2)

    assert {:ok, :from_c1} = LRUCache.get(c1, :a)
    assert {:ok, :from_c2} = LRUCache.get(c2, :a)

    # Evict from c1 only
    LRUCache.put(c1, :b, :b)
    # evicts :a from c1
    LRUCache.put(c1, :c, :c)

    assert :miss = LRUCache.get(c1, :a)
    assert {:ok, :from_c2} = LRUCache.get(c2, :a)
  end

  # -------------------------------------------------------
  # Start-up option contract
  # -------------------------------------------------------

  # A fresh cache name that cannot collide with any other test or OS process.
  defp unique_name do
    :"lru_opts_#{System.pid()}_#{System.unique_integer([:positive])}"
  end

  # Start a cache that is expected to fail, and return the exception struct
  # behind the failure. A bad option may surface either as an exception raised
  # in the caller or as an initialisation failure of the started process
  # (`{:error, {exception, stacktrace}}`, or an exit carrying the same shape);
  # all of those are accepted, and only the exception type is inspected.
  defp start_error(opts) do
    Process.flag(:trap_exit, true)

    outcome =
      try do
        LRUCache.start_link(opts)
      rescue
        exception -> {:raised, exception}
      catch
        :exit, reason -> {:exited, reason}
      end

    flush_exits()
    Process.flag(:trap_exit, false)

    case outcome do
      {:raised, exception} -> exception
      {:exited, reason} -> exception_from(reason)
      {:error, reason} -> exception_from(reason)
      {:ok, _pid} -> flunk("starting the cache with invalid options should have failed")
    end
  end

  defp exception_from({exception, stacktrace}) when is_list(stacktrace), do: exception
  defp exception_from(%{__exception__: true} = exception), do: exception
  defp exception_from(other), do: flunk("start failed without an exception: #{inspect(other)}")

  defp flush_exits do
    receive do
      {:EXIT, _pid, _reason} -> flush_exits()
    after
      0 -> :ok
    end
  end

  test "a max_size of zero is rejected at start-up" do
    assert %ArgumentError{} = start_error(name: unique_name(), max_size: 0)
  end

  test "a negative max_size is rejected at start-up" do
    assert %ArgumentError{} = start_error(name: unique_name(), max_size: -1)
  end

  test "a non-integer max_size is rejected at start-up" do
    assert %ArgumentError{} = start_error(name: unique_name(), max_size: 3.0)
    assert %ArgumentError{} = start_error(name: unique_name(), max_size: :three)
  end

  test "a missing max_size is a KeyError-style start-up failure" do
    assert %KeyError{} = start_error(name: unique_name())
  end

  test "a missing name is a KeyError-style start-up failure" do
    assert %KeyError{} = start_error(max_size: 3)
  end

  test "a max_size of one is a legal start-up option" do
    name = unique_name()
    assert {:ok, pid} = LRUCache.start_link(name: name, max_size: 1)
    assert is_pid(pid)
    assert :ok = LRUCache.put(name, :a, 1)
    assert {:ok, 1} = LRUCache.get(name, :a)
  end

  test "overwriting a key at exactly max_size evicts nothing" do
    c = start_cache(3)
    LRUCache.put(c, :a, 1)
    LRUCache.put(c, :b, 2)
    LRUCache.put(c, :c, 3)

    # Cache is exactly at max_size; overwriting a resident key must not evict.
    assert :ok = LRUCache.put(c, :b, 22)

    assert {:ok, 1} = LRUCache.get(c, :a)
    assert {:ok, 22} = LRUCache.get(c, :b)
    assert {:ok, 3} = LRUCache.get(c, :c)
  end

  test "a miss creates nothing, evicts nothing and leaves ordering untouched" do
    c = start_cache(2)
    LRUCache.put(c, :a, 1)
    LRUCache.put(c, :b, 2)

    assert :miss = LRUCache.get(c, :ghost)
    assert :miss = LRUCache.get(c, :ghost)

    # Both residents survived the misses, and :a is still the LRU.
    assert :ok = LRUCache.put(c, :d, 4)

    assert :miss = LRUCache.get(c, :a)
    assert {:ok, 2} = LRUCache.get(c, :b)
    assert {:ok, 4} = LRUCache.get(c, :d)
    assert :miss = LRUCache.get(c, :ghost)
  end

  test "falsy stored values are hits, not misses" do
    c = start_cache(3)

    LRUCache.put(c, :flag, false)
    assert {:ok, false} = LRUCache.get(c, :flag)

    LRUCache.put(c, :flag, nil)
    assert {:ok, nil} = LRUCache.get(c, :flag)

    LRUCache.put(c, :flag, false)
    assert {:ok, false} = LRUCache.get(c, :flag)
  end

  test "child_spec uses the name option as the child id" do
    name = unique_name()
    spec = LRUCache.child_spec(name: name, max_size: 2)

    assert %{id: ^name, start: {LRUCache, :start_link, [start_opts]}} = spec
    assert start_opts[:name] == name
    assert start_opts[:max_size] == 2
  end
end
