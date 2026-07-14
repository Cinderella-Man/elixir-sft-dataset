# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule LRUCache do
  @moduledoc """
  A Least Recently Used (LRU) cache backed by two ETS tables.

  ## ETS tables

  Two tables are created and owned by the GenServer process:

  | Table          | Type           | Key → Value                | Purpose               |
  |----------------|----------------|----------------------------|-----------------------|
  | `<name>_data`  | `:set`         | `key → {value, timestamp}` | O(1) key lookup       |
  | `<name>_order` | `:ordered_set` | `timestamp → key`          | O(log n) LRU eviction |

  The *timestamp* is a monotonically increasing integer counter kept in the
  GenServer state – never a wall-clock value – so the cache is fully
  deterministic and testable without any clock mocking.

  ## Write serialisation

  All mutations (put, eviction, and the touch-on-get that refreshes ordering)
  are serialised through the GenServer via `GenServer.call/2`.  Reads hit ETS
  directly for maximum throughput, but still call back into the server to
  update the LRU order after a successful lookup.

  ## Example

      {:ok, _pid} = LRUCache.start_link(name: :my_cache, max_size: 3)

      :ok = LRUCache.put(:my_cache, :a, 1)
      :ok = LRUCache.put(:my_cache, :b, 2)
      :ok = LRUCache.put(:my_cache, :c, 3)

      {:ok, 1} = LRUCache.get(:my_cache, :a)   # :a is now most-recently used

      :ok = LRUCache.put(:my_cache, :d, 4)      # cache full → evicts :b (LRU)

      :miss = LRUCache.get(:my_cache, :b)
  """

  use GenServer

  # ---------------------------------------------------------------------------
  # Child spec
  # ---------------------------------------------------------------------------

  @doc false
  def child_spec(opts) do
    name = Keyword.fetch!(opts, :name)

    %{
      id: name,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5_000
    }
  end

  # ---------------------------------------------------------------------------
  # Types
  # ---------------------------------------------------------------------------

  @type name :: atom()
  @type key :: term()
  @type value :: term()
  @type timestamp :: non_neg_integer()

  @type state :: %{
          data_table: :ets.tid(),
          order_table: :ets.tid(),
          max_size: pos_integer(),
          counter: timestamp()
        }

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Start and link an `LRUCache` process.

  ## Options

  * `:name` (required) – atom used to register the process *and* to derive the
    names of the two backing ETS tables (`<name>_data` and `<name>_order`).
  * `:max_size` (required) – maximum number of entries the cache may hold.
    Must be a positive integer.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Look up `key` in the cache named `name`.

  Returns `{:ok, value}` on a hit and updates the entry's LRU ordering so it
  is considered most-recently used.  Returns `:miss` when the key is absent.
  """
  @spec get(name(), key()) :: {:ok, value()} | :miss
  def get(name, key) do
    data_table = data_table_name(name)

    # Read directly from ETS – no GenServer round-trip for the lookup itself.
    case :ets.lookup(data_table, key) do
      [{^key, {value, _ts}}] ->
        # Serialise the ordering update through the server.
        GenServer.call(name, {:touch, key})
        {:ok, value}

      [] ->
        :miss
    end
  end

  @doc """
  Insert or update `key` with `value` in the cache named `name`.

  * **Existing key** – value is updated and the entry is promoted to
    most-recently used.
  * **New key, cache not full** – entry is inserted.
  * **New key, cache full** – the least-recently used entry is evicted first,
    then the new entry is inserted.

  Always returns `:ok`.
  """
  @spec put(name(), key(), value()) :: :ok
  def put(name, key, value) do
    GenServer.call(name, {:put, key, value})
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init(opts) do
    name = Keyword.fetch!(opts, :name)
    max_size = Keyword.fetch!(opts, :max_size)

    unless is_integer(max_size) and max_size > 0 do
      raise ArgumentError, ":max_size must be a positive integer, got: #{inspect(max_size)}"
    end

    data_table =
      :ets.new(data_table_name(name), [
        :set,
        # allow direct reads from any process
        :public,
        :named_table,
        read_concurrency: true
      ])

    order_table =
      :ets.new(order_table_name(name), [
        :ordered_set,
        # only the owner writes; no external reads needed
        :protected,
        :named_table
      ])

    state = %{
      data_table: data_table,
      order_table: order_table,
      max_size: max_size,
      counter: 0
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:touch, key}, _from, state) do
    # Re-check: the entry might have been evicted between the ETS read and now.
    case :ets.lookup(state.data_table, key) do
      [{^key, {value, old_ts}}] ->
        {new_ts, state} = next_counter(state)
        # Remove old ordering entry, insert fresh one.
        :ets.delete(state.order_table, old_ts)
        :ets.insert(state.order_table, {new_ts, key})
        :ets.insert(state.data_table, {key, {value, new_ts}})
        {:reply, :ok, state}

      [] ->
        # Entry vanished (evicted by a concurrent put) – nothing to do.
        {:reply, :ok, state}
    end
  end

  def handle_call({:put, key, value}, _from, state) do
    state =
      case :ets.lookup(state.data_table, key) do
        [{^key, {_old_value, old_ts}}] ->
          # Key exists – update value and refresh ordering.
          {new_ts, state} = next_counter(state)
          :ets.delete(state.order_table, old_ts)
          :ets.insert(state.order_table, {new_ts, key})
          :ets.insert(state.data_table, {key, {value, new_ts}})
          state

        [] ->
          # New key – evict LRU first if we are at capacity.
          state = maybe_evict(state)
          {new_ts, state} = next_counter(state)
          :ets.insert(state.order_table, {new_ts, key})
          :ets.insert(state.data_table, {key, {value, new_ts}})
          state
      end

    {:reply, :ok, state}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Increment the monotonic counter and return {new_timestamp, new_state}.
  @spec next_counter(state()) :: {timestamp(), state()}
  defp next_counter(%{counter: c} = state) do
    {c + 1, %{state | counter: c + 1}}
  end

  # Evict the LRU entry when the cache is at max capacity.
  @spec maybe_evict(state()) :: state()
  defp maybe_evict(state) do
    current_size = :ets.info(state.data_table, :size)

    if current_size >= state.max_size do
      # `first/1` on an ordered_set returns the smallest key, i.e. the oldest
      # timestamp, which is exactly the least-recently used entry.
      lru_ts = :ets.first(state.order_table)
      [{^lru_ts, lru_key}] = :ets.lookup(state.order_table, lru_ts)
      :ets.delete(state.order_table, lru_ts)
      :ets.delete(state.data_table, lru_key)
    end

    state
  end

  # Derive stable, human-readable ETS table names from the cache name.
  @spec data_table_name(name()) :: atom()
  defp data_table_name(name), do: :"#{name}_data"

  @spec order_table_name(name()) :: atom()
  defp order_table_name(name), do: :"#{name}_order"
end
```

## Test harness — implement the `# TODO` test

```elixir
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
    # TODO
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
end
```
