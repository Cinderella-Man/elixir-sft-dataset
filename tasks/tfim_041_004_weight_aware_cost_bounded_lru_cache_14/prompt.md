# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule WeightedLRUCache do
  @moduledoc """
  A cost/weight-bounded LRU cache backed by two ETS tables.

  The cache caps the *total weight* of resident entries (not their count).
  Every entry carries an explicit positive-integer weight, and the running
  total is kept exactly in sync in the GenServer state.

  ## ETS tables

  | Table          | Type           | Key → Value                       | Purpose               |
  |----------------|----------------|-----------------------------------|-----------------------|
  | `<name>_data`  | `:set`         | `key → {value, weight, timestamp}`| O(1) key lookup       |
  | `<name>_order` | `:ordered_set` | `timestamp → key`                 | O(log n) LRU eviction |

  `timestamp` is a monotonically increasing integer counter kept in state —
  never wall-clock — so recency ordering is deterministic and testable.

  ## Failure semantics of `put/4`

  * `{:error, :invalid_weight}` – weight is not a positive integer; nothing changes.
  * `{:error, :too_large}` – weight alone exceeds `max_weight`; nothing changes
    and nothing is evicted.
  * `:ok` – LRU entries are evicted one at a time until the newcomer fits, then
    it is inserted as most-recently-used. Updating an existing key releases its
    old weight first, then re-inserts it (possibly evicting *other* entries).
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
  Start and link a `WeightedLRUCache`.

  ## Options

  * `:name` (required) – atom to register the process and derive ETS table names.
  * `:max_weight` (required) – positive integer total weight budget.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Look up `key`, refreshing recency. `{:ok, value}` or `:miss`."
  @spec get(name(), key()) :: {:ok, value()} | :miss
  def get(name, key) do
    case :ets.lookup(data_table_name(name), key) do
      [{^key, {value, _weight, _ts}}] ->
        GenServer.call(name, {:touch, key})
        {:ok, value}

      [] ->
        :miss
    end
  end

  @doc """
  Insert or update `key` with `value` and `weight`. See the moduledoc for the
  `{:error, :invalid_weight}` / `{:error, :too_large}` / `:ok` semantics.
  """
  @spec put(name(), key(), value(), integer()) ::
          :ok | {:error, :invalid_weight | :too_large}
  def put(name, key, value, weight) do
    GenServer.call(name, {:put, key, value, weight})
  end

  @doc "Current total resident weight."
  @spec weight(name()) :: non_neg_integer()
  def weight(name), do: GenServer.call(name, :weight)

  @impl true
  def init(opts) do
    name = Keyword.fetch!(opts, :name)
    max_weight = Keyword.fetch!(opts, :max_weight)

    unless is_integer(max_weight) and max_weight > 0 do
      raise ArgumentError, ":max_weight must be a positive integer, got: #{inspect(max_weight)}"
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
      max_weight: max_weight,
      total_weight: 0,
      counter: 0
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:weight, _from, state) do
    {:reply, state.total_weight, state}
  end

  def handle_call({:touch, key}, _from, state) do
    case :ets.lookup(state.data_table, key) do
      [{^key, {value, w, old_ts}}] ->
        {new_ts, state} = next_counter(state)
        :ets.delete(state.order_table, old_ts)
        :ets.insert(state.order_table, {new_ts, key})
        :ets.insert(state.data_table, {key, {value, w, new_ts}})
        {:reply, :ok, state}

      [] ->
        {:reply, :ok, state}
    end
  end

  def handle_call({:put, key, value, weight}, _from, state) do
    cond do
      not (is_integer(weight) and weight > 0) ->
        {:reply, {:error, :invalid_weight}, state}

      weight > state.max_weight ->
        {:reply, {:error, :too_large}, state}

      true ->
        # Treat an update as remove-then-insert: release the old weight first.
        state = release_existing(state, key)
        state = evict_until_fits(state, weight)

        {new_ts, state} = next_counter(state)
        :ets.insert(state.order_table, {new_ts, key})
        :ets.insert(state.data_table, {key, {value, weight, new_ts}})
        state = %{state | total_weight: state.total_weight + weight}

        {:reply, :ok, state}
    end
  end

  defp next_counter(%{counter: c} = state), do: {c + 1, %{state | counter: c + 1}}

  # Remove an existing entry for `key` (if any) and reclaim its weight.
  defp release_existing(state, key) do
    case :ets.lookup(state.data_table, key) do
      [{^key, {_old_value, old_w, old_ts}}] ->
        :ets.delete(state.order_table, old_ts)
        :ets.delete(state.data_table, key)
        %{state | total_weight: state.total_weight - old_w}

      [] ->
        state
    end
  end

  # Evict LRU entries one at a time until `incoming` fits within the budget.
  defp evict_until_fits(state, incoming) do
    if state.total_weight + incoming > state.max_weight and
         :ets.info(state.data_table, :size) > 0 do
      lru_ts = :ets.first(state.order_table)
      [{^lru_ts, victim}] = :ets.lookup(state.order_table, lru_ts)
      [{^victim, {_v, victim_w, ^lru_ts}}] = :ets.lookup(state.data_table, victim)
      :ets.delete(state.order_table, lru_ts)
      :ets.delete(state.data_table, victim)
      evict_until_fits(%{state | total_weight: state.total_weight - victim_w}, incoming)
    else
      state
    end
  end

  defp data_table_name(name), do: :"#{name}_data"
  defp order_table_name(name), do: :"#{name}_order"
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule WeightedLRUCacheTest do
  use ExUnit.Case, async: false

  defp start_cache(max_weight) do
    name = :"wlru_#{System.unique_integer([:positive])}"
    start_supervised!({WeightedLRUCache, name: name, max_weight: max_weight})
    name
  end

  # -------------------------------------------------------
  # Basic get / put and weight tracking
  # -------------------------------------------------------

  test "get returns :miss for unknown key" do
    c = start_cache(10)
    assert :miss = WeightedLRUCache.get(c, :nope)
  end

  test "put and get round-trip" do
    c = start_cache(10)
    assert :ok = WeightedLRUCache.put(c, :a, "val", 3)
    assert {:ok, "val"} = WeightedLRUCache.get(c, :a)
  end

  test "weight tracks the sum of resident entry weights" do
    c = start_cache(10)
    assert WeightedLRUCache.weight(c) == 0
    WeightedLRUCache.put(c, :a, 1, 3)
    WeightedLRUCache.put(c, :b, 2, 4)
    assert WeightedLRUCache.weight(c) == 7
  end

  # -------------------------------------------------------
  # Weight-based eviction
  # -------------------------------------------------------

  test "inserting evicts LRU entries until the newcomer fits" do
    c = start_cache(10)
    WeightedLRUCache.put(c, :a, "a", 6)
    WeightedLRUCache.put(c, :b, "b", 3)
    # total 9; adding c(4) → 13 > 10 → evict LRU (:a, 6) → 3, +4 = 7 ≤ 10
    WeightedLRUCache.put(c, :c, "c", 4)

    assert :miss = WeightedLRUCache.get(c, :a)
    assert {:ok, "b"} = WeightedLRUCache.get(c, :b)
    assert {:ok, "c"} = WeightedLRUCache.get(c, :c)
    assert WeightedLRUCache.weight(c) == 7
  end

  test "a single put may evict several entries in a row" do
    c = start_cache(10)
    WeightedLRUCache.put(c, :a, "a", 4)
    WeightedLRUCache.put(c, :b, "b", 4)
    # total 8; adding big(9) → evict :a → 4, still 4+9>10 → evict :b → 0, +9 = 9
    WeightedLRUCache.put(c, :big, "big", 9)

    assert :miss = WeightedLRUCache.get(c, :a)
    assert :miss = WeightedLRUCache.get(c, :b)
    assert {:ok, "big"} = WeightedLRUCache.get(c, :big)
    assert WeightedLRUCache.weight(c) == 9
  end

  test "an entry that exactly fills the budget is allowed" do
    c = start_cache(10)
    assert :ok = WeightedLRUCache.put(c, :a, "a", 10)
    assert WeightedLRUCache.weight(c) == 10
    # next insert must evict :a to make room
    assert :ok = WeightedLRUCache.put(c, :b, "b", 1)
    assert :miss = WeightedLRUCache.get(c, :a)
    assert {:ok, "b"} = WeightedLRUCache.get(c, :b)
    assert WeightedLRUCache.weight(c) == 1
  end

  # -------------------------------------------------------
  # get refreshes recency
  # -------------------------------------------------------

  test "get saves an entry from weight eviction" do
    c = start_cache(6)
    WeightedLRUCache.put(c, :a, "a", 2)
    WeightedLRUCache.put(c, :b, "b", 2)
    WeightedLRUCache.put(c, :c, "c", 2)
    # touch :a → :b is now LRU
    WeightedLRUCache.get(c, :a)
    # adding d(2) → 6+2 > 6 → evict LRU (:b)
    WeightedLRUCache.put(c, :d, "d", 2)

    assert {:ok, "a"} = WeightedLRUCache.get(c, :a)
    assert :miss = WeightedLRUCache.get(c, :b)
    assert {:ok, "c"} = WeightedLRUCache.get(c, :c)
    assert {:ok, "d"} = WeightedLRUCache.get(c, :d)
    assert WeightedLRUCache.weight(c) == 6
  end

  # -------------------------------------------------------
  # Updating an existing key
  # -------------------------------------------------------

  test "updating a key replaces its value and adjusts total weight" do
    c = start_cache(10)
    WeightedLRUCache.put(c, :a, "a", 5)
    assert WeightedLRUCache.weight(c) == 5
    WeightedLRUCache.put(c, :a, "a2", 2)
    assert {:ok, "a2"} = WeightedLRUCache.get(c, :a)
    assert WeightedLRUCache.weight(c) == 2
  end

  test "growing an existing key's weight can evict other entries" do
    c = start_cache(10)
    WeightedLRUCache.put(c, :a, "a", 2)
    WeightedLRUCache.put(c, :b, "b", 2)
    # update :a to a big weight: release old 2 (total 2), then need room for 9
    WeightedLRUCache.put(c, :a, "a-big", 9)

    assert {:ok, "a-big"} = WeightedLRUCache.get(c, :a)
    assert :miss = WeightedLRUCache.get(c, :b)
    assert WeightedLRUCache.weight(c) == 9
  end

  # -------------------------------------------------------
  # Failure semantics
  # -------------------------------------------------------

  test "rejects an entry whose weight alone exceeds the budget without evicting" do
    c = start_cache(10)
    WeightedLRUCache.put(c, :a, "a", 8)
    assert {:error, :too_large} = WeightedLRUCache.put(c, :big, "big", 11)

    # nothing evicted, nothing inserted
    assert {:ok, "a"} = WeightedLRUCache.get(c, :a)
    assert :miss = WeightedLRUCache.get(c, :big)
    assert WeightedLRUCache.weight(c) == 8
  end

  test "rejects a non-positive or non-integer weight" do
    c = start_cache(10)
    assert {:error, :invalid_weight} = WeightedLRUCache.put(c, :a, "a", 0)
    assert {:error, :invalid_weight} = WeightedLRUCache.put(c, :b, "b", -3)
    assert {:error, :invalid_weight} = WeightedLRUCache.put(c, :c, "c", 1.5)

    assert :miss = WeightedLRUCache.get(c, :a)
    assert WeightedLRUCache.weight(c) == 0
  end

  # -------------------------------------------------------
  # Arbitrary terms + independence
  # -------------------------------------------------------

  test "stores arbitrary Elixir terms as values" do
    c = start_cache(20)
    WeightedLRUCache.put(c, :list, [1, 2, 3], 1)
    WeightedLRUCache.put(c, :map, %{a: 1}, 1)
    WeightedLRUCache.put(c, nil, nil, 1)

    assert {:ok, [1, 2, 3]} = WeightedLRUCache.get(c, :list)
    assert {:ok, %{a: 1}} = WeightedLRUCache.get(c, :map)
    assert {:ok, nil} = WeightedLRUCache.get(c, nil)
  end

  test "two cache instances are fully independent" do
    # TODO
  end
end
```
