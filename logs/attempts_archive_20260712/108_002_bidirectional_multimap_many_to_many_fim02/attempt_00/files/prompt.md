# Fill in the middle: `handle_call/3` for `BiMultiMap`

`BiMultiMap` is a GenServer maintaining a bidirectional **many-to-many** relation
between keys and values. The state is a map `%{forward: %{}, reverse: %{}}` where
`forward` maps `key => MapSet of values` and `reverse` maps `value => MapSet of
keys`. The two indexes must stay perfectly in sync — an association `{key, value}`
is present in both directions or in neither — and empty sets must be pruned so a
key or value with no associations disappears from its index entirely.

Every public function delegates to the server via `GenServer.call/2`, so all
behavior lives in the `handle_call/3` clauses. Implement `handle_call/3` (one
clause per request) so that:

- `{:put, key, value}` — records the association. Insert `value` into the forward
  set at `key` (creating a new `MapSet` if the key is new) and insert `key` into
  the reverse set at `value` (creating a new `MapSet` if the value is new). Because
  a `MapSet` is used, re-adding the same pair is an idempotent no-op. Reply `:ok`
  with the updated state.

- `{:member?, key, value}` — reply `true` if `value` is in the forward set stored
  at `key` (treat a missing key as an empty set), otherwise `false`. State is
  unchanged.

- `{:get_by_key, key}` — reply with the `MapSet` of values associated with `key`,
  or an empty `MapSet` if the key has none. State is unchanged.

- `{:get_by_value, value}` — reply with the `MapSet` of keys associated with
  `value`, or an empty `MapSet` if the value has none. State is unchanged.

- `{:delete, key, value}` — remove the single association in both directions using
  the `remove_assoc/3` helper (once forward with `key`/`value`, once reverse with
  `value`/`key`). The helper prunes a key whose set becomes empty. Reply `:ok`.

- `{:delete_key, key}` — remove `key` and all of its associations. Look up the set
  of values attached to `key`, then for each such value remove `key` from the
  reverse index via `remove_assoc/3`, and finally drop `key` from the forward
  index with `Map.delete/2`. Reply `:ok`.

- `{:delete_value, value}` — the symmetric operation: look up the set of keys
  attached to `value`, remove `value` from each key's forward set via
  `remove_assoc/3`, and drop `value` from the reverse index with `Map.delete/2`.
  Reply `:ok`.

The private helper `remove_assoc/3` and the `init/1` callback are already provided;
use them as-is.

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

  def handle_call({:put, key, value}, _from, %{forward: f, reverse: r} = s) do
    # TODO
  end

  # Drops `member` from the set stored at `k`, pruning the key when it empties.
  defp remove_assoc(map, k, member) do
    case Map.fetch(map, k) do
      {:ok, set} ->
        set = MapSet.delete(set, member)
        if MapSet.size(set) == 0, do: Map.delete(map, k), else: Map.put(map, k, set)

      :error ->
        map
    end
  end
end

```