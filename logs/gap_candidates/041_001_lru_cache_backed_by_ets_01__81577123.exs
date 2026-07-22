defmodule LRUCacheTest do
  use ExUnit.Case, async: false

  # Helper: start a uniquely named cache per test to avoid collisions
  defp start_cache(max_size) do
    name = :"lru_#{System.unique_integer([:positive])}"
    start_supervised!({LRUCache, name: name, max_size: max_size})
    name
  end

  # The backing ETS tables are part of the documented surface: they are named
  # deterministically from the `:name` option so they are stable and
  # inspectable, and the data table is readable from any process.
  defp data_table(name), do: :"#{name}_data"
  defp order_table(name), do: :"#{name}_order"

  # The documented timestamp stamped on a resident key by its last touch.
  defp timestamp(name, key) do
    [{^key, {_value, ts}}] = :ets.lookup(data_table(name), key)
    ts
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

  # -------------------------------------------------------
  # Backing ETS tables — documented, stable and inspectable
  # -------------------------------------------------------

  test "the two backing tables are named, typed and protected as documented" do
    c = start_cache(2)

    data = data_table(c)
    order = order_table(c)

    # Both tables exist under the deterministic names derived from :name.
    assert :ets.info(data, :named_table) == true
    assert :ets.info(order, :named_table) == true

    # The data table: a :set for O(1) lookups, readable from any process, and
    # optimised for the direct concurrent reads the read path performs.
    assert :ets.info(data, :type) == :set
    assert :ets.info(data, :protection) == :public
    assert :ets.info(data, :read_concurrency) == true

    # The order table: an :ordered_set so the LRU entry is found in O(log n);
    # only the owning GenServer writes to it.
    assert :ets.info(order, :type) == :ordered_set
    assert :ets.info(order, :protection) == :protected
  end

  test "a fresh cache starts its counter at 0, so the first write is stamped 1" do
    c = start_cache(3)

    assert :ok = LRUCache.put(c, :a, 1)
    assert timestamp(c, :a) == 1
  end

  test "every touch consumes exactly the next counter value" do
    c = start_cache(3)

    # New key.
    assert :ok = LRUCache.put(c, :a, 1)
    assert timestamp(c, :a) == 1

    # Another new key: the very next counter value, not a skipped one.
    assert :ok = LRUCache.put(c, :b, 2)
    assert timestamp(c, :b) == 2

    # A hit on :get is a touch and re-stamps the entry.
    assert {:ok, 1} = LRUCache.get(c, :a)
    assert timestamp(c, :a) == 3
    # ... and leaves untouched keys exactly where they were.
    assert timestamp(c, :b) == 2

    # An overwrite is a touch too.
    assert :ok = LRUCache.put(c, :b, 22)
    assert timestamp(c, :b) == 4

    # A third new key continues the same unbroken sequence.
    assert :ok = LRUCache.put(c, :c, 3)
    assert timestamp(c, :c) == 5
    assert timestamp(c, :a) == 3
  end

  test "a miss consumes no counter value at all" do
    c = start_cache(3)

    LRUCache.put(c, :a, 1)
    assert timestamp(c, :a) == 1

    assert :miss = LRUCache.get(c, :ghost)
    assert :miss = LRUCache.get(c, :ghost)

    # Had the misses burned counter values, :b would not be stamped 2.
    assert :ok = LRUCache.put(c, :b, 2)
    assert timestamp(c, :b) == 2
  end

  test "the order table holds exactly one freshly stamped row per resident key" do
    c = start_cache(2)

    LRUCache.put(c, :a, 1)
    LRUCache.put(c, :b, 2)

    # Overwrite and read :a; its stale ordering rows must be gone.
    LRUCache.put(c, :a, 11)
    assert {:ok, 11} = LRUCache.get(c, :a)

    # ts 1 (:a inserted), 2 (:b inserted), 3 (:a overwritten), 4 (:a read).
    assert :ets.tab2list(order_table(c)) == [{2, :b}, {4, :a}]

    # Evicting the LRU (:b) removes its row and stamps the newcomer next.
    LRUCache.put(c, :c, 3)
    assert :ets.tab2list(order_table(c)) == [{4, :a}, {5, :c}]
  end

  # -------------------------------------------------------
  # Start-up validation is not bypassed by the supervised path
  # -------------------------------------------------------

  test "a non-positive max_size fails the start under a supervisor too" do
    # The same option contract holds when the cache is placed under a
    # supervisor through its child_spec: the child must fail to start.
    assert {:error, _zero_reason} =
             start_supervised({LRUCache, name: unique_name(), max_size: 0})

    assert {:error, _negative_reason} =
             start_supervised({LRUCache, name: unique_name(), max_size: -1})
  end

  test "start-up rejects non-integer max_size values that compare above zero" do
    # Erlang term ordering places atoms and binaries above every integer, so a
    # cache that only checked `max_size > 0` would accept these; a max_size
    # that is not an integer must be rejected regardless of how it compares.
    assert %ArgumentError{} = start_error(name: unique_name(), max_size: true)
    assert %ArgumentError{} = start_error(name: unique_name(), max_size: "3")
  end

  test "a valid supervised start still yields a working cache of that capacity" do
    # Rejecting bad options must not come at the cost of the legal path: a
    # supervised cache started with max_size 2 holds two entries and then
    # evicts exactly the least-recently used one.
    name = unique_name()
    assert pid = start_supervised!({LRUCache, name: name, max_size: 2})
    assert is_pid(pid)

    assert :ok = LRUCache.put(name, :a, 1)
    assert :ok = LRUCache.put(name, :b, 2)
    assert :ok = LRUCache.put(name, :c, 3)

    assert :miss = LRUCache.get(name, :a)
    assert {:ok, 2} = LRUCache.get(name, :b)
    assert {:ok, 3} = LRUCache.get(name, :c)
  end
end
