# One bug. Find it. Fix it.

The module below implements the task that follows, except for a single
behavior bug. The bottom of this prompt shows the real failure report from
its (hidden) test suite. Deliver the full corrected module: smallest
possible change, no restructuring, nothing else touched.

## Target behavior

# Bidirectional Multimap (Many-to-Many) GenServer

Write me an Elixir GenServer module called `BiMultiMap` that maintains a **bidirectional many-to-many relation** between keys and values. Unlike a strict bijection, a single key may be associated with *many* values, and a single value may be associated with *many* keys. What must always hold is that the forward and reverse indexes agree perfectly: an association `key ↔ value` is either present in both directions or absent from both.

## Public API

- `BiMultiMap.start_link(opts)` — starts the process. It must accept a `:name` option used to register the process (all other functions take that name — or any valid GenServer server reference — as their first argument). Return the usual `{:ok, pid}`.

- `BiMultiMap.put(name, key, value)` — records the association between `key` and `value`. Always returns `:ok`. Adding the same `{key, value}` pair again is an idempotent no-op (the relation is a *set* of pairs, never a multiset). A key may accumulate several values and a value may accumulate several keys.

- `BiMultiMap.member?(name, key, value)` — returns `true` if the association `{key, value}` is currently present, otherwise `false`.

- `BiMultiMap.get_by_key(name, key)` — returns a `MapSet` of all values currently associated with `key` (an **empty `MapSet`** if the key has none).

- `BiMultiMap.get_by_value(name, value)` — returns a `MapSet` of all keys currently associated with `value` (an **empty `MapSet`** if the value has none).

- `BiMultiMap.delete(name, key, value)` — removes the single association `{key, value}` in both directions. Returns `:ok`. Removing an association that isn't present is a harmless no-op.

- `BiMultiMap.delete_key(name, key)` — removes `key` and *all* of its associations, cleaning up the reverse index for every value that was attached to it. Returns `:ok`.

- `BiMultiMap.delete_value(name, value)` — removes `value` and *all* of its associations, cleaning up the forward index for every key that was attached to it. Returns `:ok`.

## The invariant

At all times the forward and reverse indexes must stay consistent:

- `member?(name, k, v)` is `true` **iff** `v` is in `get_by_key(name, k)` **iff** `k` is in `get_by_value(name, v)`.
- When the last value is removed from a key (via `delete/3`, `delete_value/2`, etc.), that key must disappear entirely from the forward index — `get_by_key` returns an empty `MapSet` and the internal map no longer holds a stale empty set. The symmetric rule holds for values in the reverse index.

Keys and values can be any term (atoms, integers, strings, tuples, etc.).

Give me the complete module in a single file. Use only the OTP standard library — no external dependencies.

## The buggy module

```elixir
defmodule BiMultiMap do
  @moduledoc """
  A GenServer maintaining a bidirectional **many-to-many** relation between keys
  and values.

  A key may be associated with many values and a value with many keys; the
  relation is a set of `{key, value}` pairs. A forward index (`key => MapSet of
  values`) and a reverse index (`value => MapSet of keys`) are kept perfectly in
  sync: an association is present in both directions or in neither. Empty sets are
  pruned so a key/value with no associations disappears from its index entirely.

  Keys and values may be any term.
  """

  use GenServer

  ## Client API

  @doc """
  Starts the BiMultiMap process. Accepts a `:name` option used to register it.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    GenServer.start_link(__MODULE__, :ok, [name: name] ++ opts)
  end

  @doc "Records the association `{key, value}`. Idempotent. Returns `:ok`."
  @spec put(GenServer.server(), term(), term()) :: :ok
  def put(name, key, value), do: GenServer.call(name, {:put, key, value})

  @doc "Returns whether the association `{key, value}` is currently present."
  @spec member?(GenServer.server(), term(), term()) :: boolean()
  def member?(name, key, value), do: GenServer.call(name, {:member?, key, value})

  @doc "Returns a `MapSet` of all values associated with `key` (empty if none)."
  @spec get_by_key(GenServer.server(), term()) :: MapSet.t()
  def get_by_key(name, key), do: GenServer.call(name, {:get_by_key, key})

  @doc "Returns a `MapSet` of all keys associated with `value` (empty if none)."
  @spec get_by_value(GenServer.server(), term()) :: MapSet.t()
  def get_by_value(name, value), do: GenServer.call(name, {:get_by_value, value})

  @doc "Removes the single association `{key, value}` in both directions."
  @spec delete(GenServer.server(), term(), term()) :: :ok
  def delete(name, key, value), do: GenServer.call(name, {:delete, key, value})

  @doc "Removes `key` and all of its associations. Returns `:ok`."
  @spec delete_key(GenServer.server(), term()) :: :ok
  def delete_key(name, key), do: GenServer.call(name, {:delete_key, key})

  @doc "Removes `value` and all of its associations. Returns `:ok`."
  @spec delete_value(GenServer.server(), term()) :: :ok
  def delete_value(name, value), do: GenServer.call(name, {:delete_value, value})

  ## Server callbacks

  @impl true
  def init(:ok) do
    # forward: key => MapSet of values, reverse: value => MapSet of keys
    {:ok, %{forward: %{}, reverse: %{}}}
  end

  @impl true
  def handle_call({:put, key, value}, _from, %{forward: f, reverse: r} = s) do
    f = Map.update(f, key, MapSet.new([value]), &MapSet.put(&1, value))
    r = Map.update(r, value, MapSet.new([key]), &MapSet.put(&1, key))
    {:reply, :ok, %{s | forward: f, reverse: r}}
  end

  def handle_call({:member?, key, value}, _from, s) do
    vs = Map.get(s.forward, key, MapSet.new())
    {:reply, MapSet.member?(vs, value), s}
  end

  def handle_call({:get_by_key, key}, _from, s) do
    {:reply, Map.get(s.forward, key, MapSet.new()), s}
  end

  def handle_call({:get_by_value, value}, _from, s) do
    {:reply, Map.get(s.reverse, value, MapSet.new()), s}
  end

  def handle_call({:delete, key, value}, _from, %{forward: f, reverse: r} = s) do
    f = remove_assoc(f, key, value)
    r = remove_assoc(r, value, key)
    {:reply, :ok, %{s | forward: f, reverse: r}}
  end

  def handle_call({:delete_key, key}, _from, %{forward: f, reverse: r} = s) do
    values = Map.get(f, key, MapSet.new())
    r = Enum.reduce(values, r, fn v, r -> remove_assoc(r, v, key) end)
    {:reply, :ok, %{s | forward: Map.delete(f, key), reverse: r}}
  end

  def handle_call({:delete_value, value}, _from, %{forward: f, reverse: r} = s) do
    keys = Map.get(r, value, MapSet.new())
    f = Enum.reduce(keys, f, fn k, f -> remove_assoc(f, k, value) end)
    {:reply, :ok, %{s | forward: f, reverse: Map.delete(r, value)}}
  end

  # Drops `member` from the set stored at `k`, pruning the key when it empties.
  defp remove_assoc(map, k, member) do
    case Map.fetch(map, k) do
      {:error, set} ->
        set = MapSet.delete(set, member)
        if MapSet.size(set) == 0, do: Map.delete(map, k), else: Map.put(map, k, set)

      :error ->
        map
    end
  end
end
```

## Failing test report

```
6 of 12 test(s) failed:

  * test delete removes just one association in both directions
      :exit: {{{:case_clause, {:ok, MapSet.new([1, 2])}}, [{BiMultiMap, :remove_assoc, 3, [file: ~c".gen_staging/bugfix_108_002_bidirectional_multimap_many_to_many_02_mutant.ex", line: 104]}, {BiMultiMap, :handle_call, 3, [file: ~c".gen_staging/bugfix_108_002_bidirectional_multimap_many_to_many_02_mutant.ex", line: 85]}, {:gen_server, :try_handle_call, 4, [file: ~c"gen_server.erl", line: 2470]}, {:gen_server, :handle_msg, 3, [file: ~c"gen_server.erl", line: 2499]}, {:proc_lib, :init_p_do_apply, 3, [fi

  * test removing the last value prunes the key entirely
      :exit: {{{:case_clause, {:ok, MapSet.new([1])}}, [{BiMultiMap, :remove_assoc, 3, [file: ~c".gen_staging/bugfix_108_002_bidirectional_multimap_many_to_many_02_mutant.ex", line: 104]}, {BiMultiMap, :handle_call, 3, [file: ~c".gen_staging/bugfix_108_002_bidirectional_multimap_many_to_many_02_mutant.ex", line: 85]}, {:gen_server, :try_handle_call, 4, [file: ~c"gen_server.erl", line: 2470]}, {:gen_server, :handle_msg, 3, [file: ~c"gen_server.erl", line: 2499]}, {:proc_lib, :init_p_do_apply, 3, [file:

  * test deleting an absent association is a harmless no-op
      :exit: {{{:case_clause, {:ok, MapSet.new([1])}}, [{BiMultiMap, :remove_assoc, 3, [file: ~c".gen_staging/bugfix_108_002_bidirectional_multimap_many_to_many_02_mutant.ex", line: 104]}, {BiMultiMap, :handle_call, 3, [file: ~c".gen_staging/bugfix_108_002_bidirectional_multimap_many_to_many_02_mutant.ex", line: 85]}, {:gen_server, :try_handle_call, 4, [file: ~c"gen_server.erl", line: 2470]}, {:gen_server, :handle_msg, 3, [file: ~c"gen_server.erl", line: 2499]}, {:proc_lib, :init_p_do_apply, 3, [file:

  * test delete_key removes the key and cleans every reverse entry
      :exit: {{{:case_clause, {:ok, MapSet.new([:a, :b])}}, [{BiMultiMap, :remove_assoc, 3, [file: ~c".gen_staging/bugfix_108_002_bidirectional_multimap_many_to_many_02_mutant.ex", line: 104]}, {Enum, :"-reduce/3-anonymous-1-", 3, [file: ~c"lib/enum.ex", line: 4667]}, {Enumerable.List, :reduce, 3, [file: ~c"lib/enum.ex", line: 5119]}, {Enum, :reduce, 3, [file: ~c"lib/enum.ex", line: 4667]}, {BiMultiMap, :handle_call, 3, [file: ~c".gen_staging/bugfix_108_002_bidirectional_multimap_many_to_many_02_mutan

  (…2 more)
```
