# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

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

## Test harness — implement the `# TODO` test

```elixir
defmodule ConfigStoreTest do
  use ExUnit.Case, async: false

  defp start(opts) do
    {:ok, pid} = ConfigStore.start_link(opts)
    pid
  end

  test "base-only config is returned when no layers added" do
    s = start(base: %{a: 1, b: %{c: 2}})

    assert ConfigStore.get_config(s) == %{a: 1, b: %{c: 2}}
    assert ConfigStore.layers(s) == []
  end

  test "put_layer overrides scalars from the base" do
    s = start(base: %{host: "localhost", port: 4000})

    assert :ok == ConfigStore.put_layer(s, :env, %{port: 9000})

    assert ConfigStore.get_config(s) == %{host: "localhost", port: 9000}
    assert ConfigStore.layers(s) == [:env]
  end

  test "nested maps are deep-merged across base and layers" do
    s = start(base: %{db: %{host: "localhost", port: 5432, name: "prod"}})
    ConfigStore.put_layer(s, :override, %{db: %{port: 5433}})

    assert ConfigStore.get_config(s).db == %{host: "localhost", port: 5433, name: "prod"}
  end

  test "later layer wins over earlier layer" do
    s = start(base: %{level: :info})
    ConfigStore.put_layer(s, :file, %{level: :warn})
    ConfigStore.put_layer(s, :env, %{level: :error})

    assert ConfigStore.get_config(s).level == :error
    assert ConfigStore.layers(s) == [:file, :env]
  end

  test "replacing a layer keeps its precedence position" do
    s = start(base: %{v: 0})
    ConfigStore.put_layer(s, :low, %{v: 1})
    ConfigStore.put_layer(s, :high, %{v: 2})

    # Re-put :low with a new value; it must still be lower precedence than :high.
    ConfigStore.put_layer(s, :low, %{v: 99})

    assert ConfigStore.layers(s) == [:low, :high]
    assert ConfigStore.get_config(s).v == 2
  end

  test "drop_layer removes a layer" do
    s = start(base: %{v: 0})
    ConfigStore.put_layer(s, :a, %{v: 1})
    ConfigStore.put_layer(s, :b, %{v: 2})

    assert :ok == ConfigStore.drop_layer(s, :b)

    assert ConfigStore.layers(s) == [:a]
    assert ConfigStore.get_config(s).v == 1
  end

  test "get/2 fetches by key-path and returns nil when absent" do
    s = start(base: %{app: %{server: %{port: 80}}})
    ConfigStore.put_layer(s, :env, %{app: %{server: %{port: 443}}})

    assert ConfigStore.get(s, [:app, :server, :port]) == 443
    assert ConfigStore.get(s, [:app, :missing]) == nil
  end

  test "append list strategy concatenates base and layer lists" do
    # TODO
  end

  test "per-key list strategy overrides the global strategy" do
    s =
      start(
        base: %{tags: ["a"], plugins: ["core"]},
        list_strategy: :replace,
        list_strategies: %{[:tags] => :append}
      )

    ConfigStore.put_layer(s, :env, %{tags: ["b"], plugins: ["extra"]})

    cfg = ConfigStore.get_config(s)
    assert cfg.tags == ["a", "b"]
    assert cfg.plugins == ["extra"]
  end

  test "locked key-path cannot be changed by any layer" do
    s = start(base: %{db: %{password: "s3cr3t", host: "localhost"}}, locked: [[:db, :password]])
    ConfigStore.put_layer(s, :env, %{db: %{password: "pwned", host: "evil.host"}})

    cfg = ConfigStore.get_config(s)
    assert cfg.db.password == "s3cr3t"
    assert cfg.db.host == "evil.host"
  end

  test "named server can be addressed by its registered name" do
    {:ok, _pid} = ConfigStore.start_link(name: :cfg_named_test, base: %{a: 1})
    ConfigStore.put_layer(:cfg_named_test, :env, %{a: 2})

    assert ConfigStore.get(:cfg_named_test, [:a]) == 2
  end
end
```
