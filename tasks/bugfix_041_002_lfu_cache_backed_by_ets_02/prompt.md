# Fix the bug

The module below was written for the task that follows, but ONE behavior bug
slipped in. The test suite (not shown) fails with the report at the bottom.
Find the bug and fix it — change as little as possible; do not restructure
working code. Reply with the complete corrected module.

## The task the module implements

Write me an Elixir GenServer module called `LFUCache` that implements a **Least Frequently Used** cache backed by ETS.

Unlike an LRU cache (which evicts the entry that was accessed least recently), this cache evicts the entry that has been accessed the *fewest times*. When two entries are tied on access frequency, break the tie by evicting the one that is least recently used among them.

## Public API

- `LFUCache.start_link(opts)` to start the process. It should accept a `:name` option (required) used both to register the process and to name the ETS tables, and a `:max_size` option (required) that caps how many entries the cache may hold at once.
- `LFUCache.get(name, key)` which looks up a key. Return `{:ok, value}` if the key exists, or `:miss` if it does not. A successful get counts as one access and must increment that entry's frequency.
- `LFUCache.put(name, key, value)` which inserts or updates an entry. A brand-new entry starts with a frequency of 1. If the key already exists, update its value and count the write as an access (increment its frequency). If the cache is already at `max_size` and the key is new, evict the least frequently used entry (tie broken by least recently used) before inserting. Always return `:ok`.

## Behaviour contract

### `start_link/1`

- `:name` is required and is an atom. It registers the GenServer under that name, so every later call takes the same atom as its first argument. It also derives the two ETS table names: `:"<name>_data"` and `:"<name>_order"`. Both are named tables, so those exact atoms are the tables' names and callers may inspect them (e.g. `:ets.info(:"<name>_data", :size)` is the current entry count).
- `:max_size` is required and must be a positive integer (`> 0`). If it is missing, or if it is present but is not an integer or is not greater than zero (e.g. `0`, `-1`, `1.5`, `:many`), starting the cache must fail with an `ArgumentError` raised during initialisation. A missing `:name` likewise fails with the error `Keyword.fetch!/2` raises.
- The data table must be readable from any process (so `get/2` can read it without going through the server); the order table need not be.
- A freshly started cache is empty: any `get/2` on it returns `:miss`.

### `get/2`

- On a hit, returns `{:ok, value}` and, as a side effect, increments that entry's frequency by 1 and refreshes its recency to "most recently used". The frequency bump is committed before `get/2` returns, so a subsequent `put/3` that triggers eviction already sees the new frequency.
- On a miss, returns `:miss` and changes nothing: no entry is created, no frequency changes, no recency changes, and no eviction happens. Repeated misses on the same unknown key stay `:miss` forever until a `put/3` creates it.
- `get/2` never evicts anything and never changes the number of entries.
- Any term may be used as a key (atoms, tuples, integers, …) and any term as a value; keys are compared as ETS `:set` keys.

### `put/3`

- Always returns `:ok` — there is no error return, and no way for a caller to observe *which* entry (if any) was evicted from the return value.
- **New key, cache below `max_size`:** the entry is inserted with frequency `1` and becomes the most recently used entry. Nothing is evicted.
- **Existing key:** the value is overwritten, the frequency is incremented by 1, and the entry becomes the most recently used. The entry count does not change, and **no eviction occurs even when the cache is exactly at `max_size`** — updating a key that is already present must never evict anything, not even itself.
- **New key, cache exactly at `max_size`:** exactly one entry is evicted *before* the new one is inserted, so the entry count after the call is still `max_size`. The victim is the entry with the lowest frequency; among entries tied at that lowest frequency, the victim is the one accessed longest ago. The evicted key is fully gone: a later `get/2` for it returns `:miss`, and re-`put`ting it starts it over at frequency `1` (its old frequency is not remembered).
- With `max_size: 1`, putting a second, different key evicts the first one, leaving exactly one entry.

### Recency and ordering

- "Recency" is a single monotonically increasing counter (`seq`) held in the GenServer state — never a wall-clock value — so ordering is deterministic and reproducible without any clock mocking.
- Every access draws a fresh, strictly larger `seq`: a hit in `get/2`, a `put/3` that inserts, and a `put/3` that updates. A `get/2` miss draws nothing and must not perturb the ordering of other entries.
- Ordering is therefore total: no two live entries ever share a recency stamp, so the eviction victim is always unique and eviction is fully deterministic given the sequence of calls.
- Consequence worth stating explicitly: touching an entry (via `get/2` or an update `put/3`) both raises its frequency *and* makes it the newest, so it moves to the back of the eviction queue on both axes.

## Implementation requirements

- Use two ETS tables owned by the GenServer: one that maps `key → {value, frequency, seq}` for O(1) lookups — each row stored literally as the two-element tuple `{key, {value, frequency, seq}}` (the triple nested, not flattened into the row), since callers may read rows directly — and one ordered set whose key is the composite `{frequency, seq}` (mapping to the cache key) so the least-frequently-used entry — with a least-recently-used tie-break — is always at the front for O(log n) eviction.
- The two tables must stay consistent: for every key in the data table there is exactly one entry in the order table, keyed by that key's current `{frequency, seq}` — stale composite keys must be removed when an entry is touched, updated, or evicted.
- All mutations (`put`, eviction, and the frequency bump on `get`) must go through the GenServer process to serialise writes; reads may read directly from ETS first. Because mutations are serialised through synchronous calls, concurrent callers observe a single well-defined interleaving.
- A frequency bump requested for a key that has since vanished (e.g. it was evicted between the direct ETS read and the server call) must be a harmless no-op rather than a crash or a resurrected entry.
- There is no TTL, no background cleanup, and no maximum frequency: entries only leave the cache through frequency-based eviction, and frequencies grow without bound.
- Provide a `child_spec/1` so the cache can be placed directly in a supervision tree with the same `opts` keyword list.

Give me the complete module in a single file. Use only the OTP standard library — no external dependencies.

## The buggy module

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

    # A missing :max_size fails like an invalid one — ArgumentError, not the
    # KeyError a fetch! would raise (the contract reserves that for :name).
    max_size =
      case Keyword.fetch(opts, :max_size) do
        {:ok, value} -> value
        :error -> raise ArgumentError, ":max_size is required"
      end

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
        :ets.insert(state.order_table, {{freq - 1, new_seq}, key})
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

## Failing test report

```
5 of 20 test(s) failed:

  * test least frequently used entry is evicted, not least recently used
      
      
      match (=) failed
      code:  assert {:ok, 1} = LFUCache.get(c, :a)
      left:  {:ok, 1}
      right: :miss
      

  * test repeated gets protect a hot key across several evictions
      
      
      match (=) failed
      code:  assert :miss = LFUCache.get(c, :b)
      left:  :miss
      right: {:ok, 2}
      

  * test a get bumps frequency by exactly one, so a twice-read key outranks a once-read key
      
      
      match (=) failed
      code:  assert {:ok, 1} = LFUCache.get(c, :a)
      left:  {:ok, 1}
      right: :miss
      

  * test an evicted key leaves no row behind and restarts at frequency 1 when re-put
      
      
      Assertion with == failed
      code:  assert :ets.lookup(data, :b) == []
      left:  [b: {2, 3, 7}]
      right: []
      

  (…1 more)
```
