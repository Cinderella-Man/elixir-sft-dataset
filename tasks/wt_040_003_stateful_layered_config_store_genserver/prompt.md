# Write tests for this module

Below is a completed Elixir module and the original specification it was built to
satisfy. Write a comprehensive ExUnit test harness that verifies a correct
implementation of this module.

Requirements for the harness:
- Define a module `<Module>Test` that does `use ExUnit.Case, async: false`.
- Do NOT call `ExUnit.start()` — the evaluator starts ExUnit itself.
- Make it self-contained: any fakes, clock Agents, or helpers are defined inline.
- Cover the full public API and the important edge cases described in the spec.
- It must compile with ZERO warnings (prefix unused variables with `_`; match float
  zero as `+0.0`/`-0.0`).
- Give me the complete harness in a single file.

## Original specification

Write me an Elixir module called `ConfigStore` implemented as a **GenServer** that
holds a base configuration plus a dynamic, ordered set of named override layers and
computes the deep-merged effective configuration on demand.

Public API:
- `ConfigStore.start_link(opts)` — starts the server. Supported opts:
  - `:base` — the base config map (default `%{}`).
  - `:name` — optional GenServer name.
  - `:list_strategy` — `:replace` (default) or `:append`, global list merge strategy.
  - `:list_strategies` — a map of `key_path => :replace | :append` (paths as lists or
    tuples of atoms) overriding the global strategy per path.
  - `:locked` — a list of key-path tuples/lists that override layers must not change.
- `ConfigStore.put_layer(server, layer_name, config_map)` — adds a named override
  layer, or replaces an existing one **in place** (keeping its precedence position).
  Returns `:ok`.
- `ConfigStore.drop_layer(server, layer_name)` — removes a layer. Returns `:ok`.
- `ConfigStore.layers(server)` — returns the list of layer names in precedence order
  (lowest precedence first).
- `ConfigStore.get_config(server)` — returns the deep-merged effective config: the
  base with every layer applied in order, later layers winning.
- `ConfigStore.get(server, key_path)` — returns the effective value at a key-path
  (list of atoms), or `nil` if absent.

Merge rules match a standard deep config merge:
- Nested maps are deep-merged, not replaced wholesale.
- Scalars from higher-precedence layers replace lower ones.
- Lists follow the `:list_strategy` / `:list_strategies` options (`:append`
  concatenates onto the accumulated list).
- Locked key-paths keep the base value and cannot be changed by any layer.

Layers apply in insertion order: the first `put_layer` is lowest precedence; a later
`put_layer` with the same name updates the existing layer without changing its spot.

Give me the complete module in a single file. Use only the Elixir standard library.

## Module under test

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

    Map.new(keys, fn k ->
      kpath = path ++ [k]

      value =
        cond do
          not Map.has_key?(over, k) -> Map.fetch!(base, k)
          not Map.has_key?(base, k) -> Map.fetch!(over, k)
          locked?(kpath, opts) -> Map.fetch!(base, k)
          true -> merge_value(Map.fetch!(base, k), Map.fetch!(over, k), kpath, opts)
        end

      {k, value}
    end)
  end

  defp merge_value(bv, ov, kpath, opts) do
    cond do
      is_map(bv) and is_map(ov) ->
        do_merge(bv, ov, kpath, opts)

      is_list(bv) and is_list(ov) ->
        case list_strategy_for(kpath, opts) do
          :replace -> ov
          :append -> bv ++ ov
        end

      true ->
        ov
    end
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
