# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule LFUCache do
  @moduledoc """
  A Least Frequently Used (LFU) cache backed by two ETS tables.

  ## ETS tables

  | Table          | Type           | Key → Value                     | Purpose        |
  |----------------|----------------|---------------------------------|----------------|
  | `<name>_data`  | `:set`         | `key → {value, frequency, seq}` | O(1) lookup    |
  | `<name>_order` | `:ordered_set` | `{frequency, seq} → key`        | O(log n) evict |

  Eviction removes the entry with the smallest `{frequency, seq}` composite key.
  Because `frequency` is compared first, the *least frequently used* entry goes
  first; ties on frequency fall back to the smallest `seq`, i.e. the *least
  recently used* among equally-frequent entries.

  `seq` is a monotonically increasing integer counter kept in the GenServer
  state — never a wall-clock value — so ordering is deterministic and fully
  testable without any clock mocking. Every access (get, put-insert,
  put-update) draws a fresh `seq`.

  All mutations are serialised through the GenServer; reads consult ETS
  directly first, then bump the frequency through the server.
  """

  use GenServer

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

  @type name :: atom()
  @type key :: term()
  @type value :: term()

  @doc """
  Start and link an `LFUCache` process.

  ## Options

  * `:name` (required) – atom used to register the process and derive the ETS
    table names (`<name>_data` and `<name>_order`).
  * `:max_size` (required) – maximum number of entries; a positive integer.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Look up `key`. Returns `{:ok, value}` (and increments the entry's frequency)
  on a hit, or `:miss` when the key is absent.
  """
  @spec get(name(), key()) :: {:ok, value()} | :miss
  def get(name, key) do
    case :ets.lookup(data_table_name(name), key) do
      [{^key, {value, _freq, _seq}}] ->
        GenServer.call(name, {:touch, key})
        {:ok, value}

      [] ->
        :miss
    end
  end

  @doc """
  Insert or update `key` with `value`.

  A new entry starts at frequency 1. Updating an existing key refreshes its
  value and increments its frequency. When the cache is full and the key is
  new, the least-frequently-used entry (LRU tie-break) is evicted first.
  Always returns `:ok`.
  """
  @spec put(name(), key(), value()) :: :ok
  def put(name, key, value) do
    GenServer.call(name, {:put, key, value})
  end

  @impl true
  def init(opts) do
    name = Keyword.fetch!(opts, :name)
    max_size = Keyword.fetch!(opts, :max_size)

    unless is_integer(max_size) and max_size > 0 do
      raise ArgumentError, ":max_size must be a positive integer, got: #{inspect(max_size)}"
    end

    data_table =
      :ets.new(data_table_name(name), [
        :set,
        :public,
        :named_table,
        read_concurrency: true
      ])

    order_table =
      :ets.new(order_table_name(name), [
        :ordered_set,
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

  @impl true
  def handle_call({:touch, key}, _from, state) do
    case :ets.lookup(state.data_table, key) do
      [{^key, {value, freq, seq}}] ->
        {new_seq, state} = next_counter(state)
        :ets.delete(state.order_table, {freq, seq})
        :ets.insert(state.order_table, {{freq + 1, new_seq}, key})
        :ets.insert(state.data_table, {key, {value, freq + 1, new_seq}})
        {:reply, :ok, state}

      [] ->
        {:reply, :ok, state}
    end
  end

  def handle_call({:put, key, value}, _from, state) do
    state =
      case :ets.lookup(state.data_table, key) do
        [{^key, {_old_value, freq, seq}}] ->
          {new_seq, state} = next_counter(state)
          :ets.delete(state.order_table, {freq, seq})
          :ets.insert(state.order_table, {{freq + 1, new_seq}, key})
          :ets.insert(state.data_table, {key, {value, freq + 1, new_seq}})
          state

        [] ->
          state = maybe_evict(state)
          {new_seq, state} = next_counter(state)
          :ets.insert(state.order_table, {{1, new_seq}, key})
          :ets.insert(state.data_table, {key, {value, 1, new_seq}})
          state
      end

    {:reply, :ok, state}
  end

  defp next_counter(%{counter: c} = state), do: {c + 1, %{state | counter: c + 1}}

  defp maybe_evict(state) do
    if :ets.info(state.data_table, :size) >= state.max_size do
      # Smallest composite key = lowest frequency, LRU tie-break.
      victim_composite = :ets.first(state.order_table)
      [{^victim_composite, victim_key}] = :ets.lookup(state.order_table, victim_composite)
      :ets.delete(state.order_table, victim_composite)
      :ets.delete(state.data_table, victim_key)
    end

    state
  end

  defp data_table_name(name), do: :"#{name}_data"
  defp order_table_name(name), do: :"#{name}_order"
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule LFUCacheTest do
  use ExUnit.Case, async: false

  defp start_cache(max_size) do
    name = :"lfu_#{System.unique_integer([:positive])}"
    start_supervised!({LFUCache, name: name, max_size: max_size})
    name
  end

  # -------------------------------------------------------
  # Basic get / put
  # -------------------------------------------------------

  test "get returns :miss for unknown key" do
    c = start_cache(3)
    assert :miss = LFUCache.get(c, :nope)
  end

  test "put and get round-trip" do
    c = start_cache(3)
    assert :ok = LFUCache.put(c, :a, 1)
    assert {:ok, 1} = LFUCache.get(c, :a)
  end

  test "put overwrites an existing key" do
    c = start_cache(3)
    LFUCache.put(c, :a, 1)
    LFUCache.put(c, :a, 42)
    assert {:ok, 42} = LFUCache.get(c, :a)
  end

  test "multiple distinct keys coexist" do
    c = start_cache(5)
    for i <- 1..5, do: LFUCache.put(c, i, i * 10)

    for i <- 1..5 do
      expected = i * 10
      assert {:ok, ^expected} = LFUCache.get(c, i)
    end
  end

  # -------------------------------------------------------
  # LFU eviction — frequency beats recency
  # -------------------------------------------------------

  test "least frequently used entry is evicted, not least recently used" do
    c = start_cache(2)
    LFUCache.put(c, :a, 1)
    # bump :a's frequency to 2
    assert {:ok, 1} = LFUCache.get(c, :a)
    # :b is inserted more recently than :a but has frequency 1
    LFUCache.put(c, :b, 2)

    # inserting :c evicts the LFU entry — :b (freq 1), even though it is MRU
    LFUCache.put(c, :c, 3)

    assert {:ok, 1} = LFUCache.get(c, :a)
    assert :miss = LFUCache.get(c, :b)
    assert {:ok, 3} = LFUCache.get(c, :c)
  end

  test "put-update counts as an access and raises frequency" do
    c = start_cache(2)
    LFUCache.put(c, :a, 1)
    # updating :a bumps its frequency to 2
    LFUCache.put(c, :a, 11)
    LFUCache.put(c, :b, 2)

    # :b has frequency 1, :a has frequency 2 → evict :b
    LFUCache.put(c, :c, 3)

    assert {:ok, 11} = LFUCache.get(c, :a)
    assert :miss = LFUCache.get(c, :b)
    assert {:ok, 3} = LFUCache.get(c, :c)
  end

  test "repeated gets protect a hot key across several evictions" do
    c = start_cache(3)
    LFUCache.put(c, :hot, 1)
    LFUCache.put(c, :b, 2)
    LFUCache.put(c, :c, 3)

    # make :hot very frequent
    for _ <- 1..5, do: LFUCache.get(c, :hot)

    # :b and :c both have freq 1; inserting :d evicts one of them (the LRU: :b)
    LFUCache.put(c, :d, 4)
    assert :miss = LFUCache.get(c, :b)
    assert {:ok, 1} = LFUCache.get(c, :hot)

    # inserting :e evicts :c next; :hot still survives
    LFUCache.put(c, :e, 5)
    assert :miss = LFUCache.get(c, :c)
    assert {:ok, 1} = LFUCache.get(c, :hot)
    assert {:ok, 4} = LFUCache.get(c, :d)
    assert {:ok, 5} = LFUCache.get(c, :e)
  end

  # -------------------------------------------------------
  # Tie-break by recency among equal frequencies
  # -------------------------------------------------------

  test "ties on frequency are broken by least recently used" do
    c = start_cache(3)
    # all three inserted at freq 1, in order :a, :b, :c
    LFUCache.put(c, :a, 1)
    LFUCache.put(c, :b, 2)
    LFUCache.put(c, :c, 3)

    # inserting :d evicts the LRU among the freq-1 entries → :a
    LFUCache.put(c, :d, 4)

    assert :miss = LFUCache.get(c, :a)
    assert {:ok, 2} = LFUCache.get(c, :b)
    assert {:ok, 3} = LFUCache.get(c, :c)
    assert {:ok, 4} = LFUCache.get(c, :d)
  end

  # -------------------------------------------------------
  # Size-1 edge case
  # -------------------------------------------------------

  test "cache of size 1 always holds only the latest inserted entry" do
    c = start_cache(1)
    LFUCache.put(c, :a, 1)
    LFUCache.put(c, :b, 2)

    assert :miss = LFUCache.get(c, :a)
    assert {:ok, 2} = LFUCache.get(c, :b)
  end

  # -------------------------------------------------------
  # Arbitrary terms
  # -------------------------------------------------------

  test "cache stores arbitrary Elixir terms as values" do
    c = start_cache(5)
    LFUCache.put(c, :list, [1, 2, 3])
    LFUCache.put(c, :map, %{a: 1})
    LFUCache.put(c, nil, nil)

    assert {:ok, [1, 2, 3]} = LFUCache.get(c, :list)
    assert {:ok, %{a: 1}} = LFUCache.get(c, :map)
    assert {:ok, nil} = LFUCache.get(c, nil)
  end

  # -------------------------------------------------------
  # Independent instances
  # -------------------------------------------------------

  test "two cache instances are fully independent" do
    # TODO
  end

  # -------------------------------------------------------
  # :max_size validation (init raises ArgumentError)
  # -------------------------------------------------------

  test "start_link fails with ArgumentError unless :max_size is a positive integer" do
    Process.flag(:trap_exit, true)

    for bad <- [0, -1, 1.5, :many] do
      name = :"lfu_bad_#{System.pid()}_#{System.unique_integer([:positive])}"

      assert {:error, {%ArgumentError{}, _stack}} =
               LFUCache.start_link(name: name, max_size: bad)
    end
  end

  # -------------------------------------------------------
  # Frequency arithmetic: each access is worth exactly +1
  # -------------------------------------------------------

  test "a get bumps frequency by exactly one, so a twice-read key outranks a once-read key" do
    c = start_cache(2)

    # :a reaches frequency 3 (insert + two gets)
    LFUCache.put(c, :a, 1)
    assert {:ok, 1} = LFUCache.get(c, :a)
    assert {:ok, 1} = LFUCache.get(c, :a)

    # :b reaches frequency 2 (insert + one get) and is the most recently used
    LFUCache.put(c, :b, 2)
    assert {:ok, 2} = LFUCache.get(c, :b)

    # cache is full: the lowest frequency loses — :b (freq 2) not :a (freq 3)
    LFUCache.put(c, :c, 3)

    assert {:ok, 1} = LFUCache.get(c, :a)
    assert :miss = LFUCache.get(c, :b)
    assert {:ok, 3} = LFUCache.get(c, :c)
  end

  test "a put-update bumps frequency by exactly one, so extra writes outrank fewer writes" do
    c = start_cache(2)

    # :a reaches frequency 3 (insert + two updates)
    LFUCache.put(c, :a, 1)
    LFUCache.put(c, :a, 2)
    LFUCache.put(c, :a, 3)

    # :b reaches frequency 2 (insert + one update) and is the most recently used
    LFUCache.put(c, :b, 1)
    LFUCache.put(c, :b, 2)

    # cache is full: the lowest frequency loses — :b (freq 2) not :a (freq 3)
    LFUCache.put(c, :c, 9)

    assert {:ok, 3} = LFUCache.get(c, :a)
    assert :miss = LFUCache.get(c, :b)
    assert {:ok, 9} = LFUCache.get(c, :c)
  end

  # -------------------------------------------------------
  # Entry count: updates never evict, new keys evict exactly one
  # -------------------------------------------------------

  test "entry count stays at max_size: updates evict nothing, a new key evicts exactly one" do
    c = start_cache(2)
    data = :"#{c}_data"

    LFUCache.put(c, :a, 1)
    LFUCache.put(c, :b, 2)
    assert :ets.info(data, :size) == 2

    # updating an existing key while exactly at max_size must not evict anything
    LFUCache.put(c, :a, 11)
    assert :ets.info(data, :size) == 2
    assert {:ok, 11} = LFUCache.get(c, :a)
    assert {:ok, 2} = LFUCache.get(c, :b)

    # a new key while at max_size evicts exactly one entry before inserting
    LFUCache.put(c, :c, 3)
    assert :ets.info(data, :size) == 2
    assert {:ok, 3} = LFUCache.get(c, :c)
  end
end
```
