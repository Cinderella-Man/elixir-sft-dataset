Implement the private `merge_value/4` function. It decides how a single value from a
lower-precedence layer (`bv`, the accumulated base value) and a higher-precedence
layer (`ov`, the override value) combine at key-path `kpath`, given the resolved
`opts`. When both values are maps, deep-merge them by recursing into `do_merge/4`
with the same `kpath` and `opts`. When both values are lists, consult
`list_strategy_for/2` for that path: `:replace` yields the override list `ov`, while
`:append` yields the concatenation `bv ++ ov`. In every other case (scalars, or
mismatched types) the higher-precedence value `ov` wins and is returned as-is.

```elixir
defmodule ConfigStore do
  @moduledoc """
  A GenServer that holds a base configuration plus a dynamic, ordered set of named
  override layers and computes the deep-merged effective configuration on demand.

  Layers apply in insertion order (lowest precedence first). Merge semantics match a
  standard deep config merge: nested maps recurse, scalars from higher layers win,
  lists follow `:list_strategy` / `:list_strategies`, and `:locked` paths keep the
  base value.
  """

  use GenServer

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the config store.

  Supported options: `:base`, `:name`, `:list_strategy`, `:list_strategies` and
  `:locked`. See the module documentation for their meaning.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {base, opts1} = Keyword.pop(opts, :base, %{})
    {name, opts2} = Keyword.pop(opts1, :name)

    resolved = resolve_opts(opts2)
    state = %{base: base, layers: [], opts: resolved}

    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, state, gen_opts)
  end

  @doc """
  Adds a named override layer, or replaces an existing one in place, keeping its
  precedence position. Returns `:ok`.
  """
  @spec put_layer(GenServer.server(), term(), map()) :: :ok
  def put_layer(server, layer_name, config_map) when is_map(config_map) do
    GenServer.call(server, {:put_layer, layer_name, config_map})
  end

  @doc """
  Removes the layer named `layer_name`. Returns `:ok`.
  """
  @spec drop_layer(GenServer.server(), term()) :: :ok
  def drop_layer(server, layer_name) do
    GenServer.call(server, {:drop_layer, layer_name})
  end

  @doc """
  Returns the list of layer names in precedence order (lowest precedence first).
  """
  @spec layers(GenServer.server()) :: [term()]
  def layers(server), do: GenServer.call(server, :layers)

  @doc """
  Returns the deep-merged effective config: the base with every layer applied in
  order, later layers winning.
  """
  @spec get_config(GenServer.server()) :: map()
  def get_config(server), do: GenServer.call(server, :get_config)

  @doc """
  Returns the effective value at `key_path` (a list of atoms), or `nil` if absent.
  """
  @spec get(GenServer.server(), [atom()]) :: term()
  def get(server, key_path) when is_list(key_path) do
    GenServer.call(server, {:get, key_path})
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call({:put_layer, name, map}, _from, state) do
    layers =
      if List.keymember?(state.layers, name, 0) do
        List.keyreplace(state.layers, name, 0, {name, map})
      else
        state.layers ++ [{name, map}]
      end

    {:reply, :ok, %{state | layers: layers}}
  end

  def handle_call({:drop_layer, name}, _from, state) do
    {:reply, :ok, %{state | layers: List.keydelete(state.layers, name, 0)}}
  end

  def handle_call(:layers, _from, state) do
    {:reply, Enum.map(state.layers, fn {name, _map} -> name end), state}
  end

  def handle_call(:get_config, _from, state) do
    {:reply, compute(state), state}
  end

  def handle_call({:get, key_path}, _from, state) do
    {:reply, fetch_path(compute(state), key_path), state}
  end

  # ---------------------------------------------------------------------------
  # Merge engine
  # ---------------------------------------------------------------------------

  defp compute(%{base: base, layers: layers, opts: opts}) do
    Enum.reduce(layers, base, fn {_name, map}, acc -> do_merge(acc, map, [], opts) end)
  end

  defp do_merge(base, over, path, opts) when is_map(base) and is_map(over) do
    keys = Enum.uniq(Map.keys(base) ++ Map.keys(over))

    Enum.reduce(keys, %{}, fn k, acc ->
      kpath = path ++ [k]

      cond do
        locked?(kpath, opts) ->
          # A locked path always keeps the base value — including its absence, so a
          # layer cannot introduce a key that the base never defined.
          case Map.fetch(base, k) do
            {:ok, v} -> Map.put(acc, k, v)
            :error -> acc
          end

        not Map.has_key?(over, k) ->
          Map.put(acc, k, Map.fetch!(base, k))

        not Map.has_key?(base, k) ->
          # An introduced subtree cannot smuggle in locked descendants: merging
          # it into an empty base applies the locked-keeps-absence rule at
          # every depth below this key.
          case Map.fetch!(over, k) do
            %{} = subtree -> Map.put(acc, k, do_merge(%{}, subtree, kpath, opts))
            v -> Map.put(acc, k, v)
          end

        true ->
          Map.put(acc, k, merge_value(Map.fetch!(base, k), Map.fetch!(over, k), kpath, opts))
      end
    end)
  end

  defp merge_value(bv, ov, kpath, opts) do
    # TODO
  end

  # ---------------------------------------------------------------------------
  # Options + helpers
  # ---------------------------------------------------------------------------

  defp resolve_opts(opts) do
    global = Keyword.get(opts, :list_strategy, :replace)

    per_key =
      opts
      |> Keyword.get(:list_strategies, %{})
      |> Map.new(fn {path, strat} -> {normalise_path(path), strat} end)

    locked = Enum.map(Keyword.get(opts, :locked, []), &normalise_path/1)

    %{global_list_strategy: global, per_key_strategies: per_key, locked_paths: locked}
  end

  defp normalise_path(path) when is_list(path), do: path
  defp normalise_path(path) when is_tuple(path), do: Tuple.to_list(path)

  defp locked?(kpath, %{locked_paths: locked}), do: kpath in locked

  defp list_strategy_for(kpath, %{per_key_strategies: per_key, global_list_strategy: global}) do
    Map.get(per_key, kpath, global)
  end

  defp fetch_path(map, []), do: map

  defp fetch_path(map, [k | rest]) when is_map(map) do
    case Map.fetch(map, k) do
      {:ok, v} -> fetch_path(v, rest)
      :error -> nil
    end
  end

  defp fetch_path(_map, _path), do: nil
end
```