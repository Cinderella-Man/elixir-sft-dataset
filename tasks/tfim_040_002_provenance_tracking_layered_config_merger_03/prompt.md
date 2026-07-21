# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule LayeredConfig do
  @moduledoc """
  Merges an ordered stack of named configuration layers into a single effective
  configuration and reports the provenance of every effective value.

  `merge/2` takes a non-empty list of `{layer_name, config_map}` tuples in
  increasing precedence order and returns `%{config: map, provenance: map}` where
  `provenance` maps each leaf key-path (a list of atoms) to the layer that supplied
  the winning value (or, for appended lists, the ordered list of contributing
  layers).
  """

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Merges `layers` (a non-empty list of `{name, config_map}` tuples in increasing
  precedence order) into a single effective configuration.

  Returns a map with two keys: `:config`, the deep-merged configuration, and
  `:provenance`, a map from each leaf key-path (a list of atoms) to the layer name
  that supplied the winning value. For appended lists the provenance is the ordered
  list of contributing layer names.

  Supported `opts`:

    * `:list_strategy` — `:replace` (default) or `:append` for list leaves.
    * `:list_strategies` — a map of `key_path => :replace | :append` overriding the
      global strategy for specific paths.
    * `:locked` — a list of key-paths that, once set by a lower layer, cannot be
      changed by higher layers.

  Key paths for `:list_strategies` and `:locked` are lists or tuples of atoms.
  Raises `ArgumentError` when `layers` is empty.
  """
  @spec merge([{term(), map()}], keyword()) :: %{config: map(), provenance: map()}
  def merge(layers, opts \\ []) when is_list(layers) do
    if layers == [] do
      raise ArgumentError, "`layers` must be a non-empty list of {name, map} tuples"
    end

    resolved = resolve_opts(opts)

    [{first_name, first_map} | rest] = Enum.map(layers, &normalise_layer/1)
    init_prov = leaf_provenance(first_map, first_name, [], %{})

    {config, provenance} =
      Enum.reduce(rest, {first_map, init_prov}, fn {name, map}, {acc_map, acc_prov} ->
        merge_map(acc_map, map, name, [], acc_prov, resolved)
      end)

    %{config: config, provenance: provenance}
  end

  # ---------------------------------------------------------------------------
  # Layer / option normalisation
  # ---------------------------------------------------------------------------

  defp normalise_layer({name, map}) when is_map(map), do: {name, map}

  defp normalise_layer(other) do
    raise ArgumentError, "each layer must be a {name, map} tuple, got: #{inspect(other)}"
  end

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

  defp normalise_path(path) do
    raise ArgumentError, "key paths must be lists or tuples of atoms, got: #{inspect(path)}"
  end

  # ---------------------------------------------------------------------------
  # Recursive merge (threads the provenance map through)
  # ---------------------------------------------------------------------------

  defp merge_map(base_map, over_map, name, path, prov, opts) do
    Enum.reduce(over_map, {base_map, prov}, fn {k, ov}, {acc, pr} ->
      kpath = path ++ [k]

      cond do
        locked?(kpath, opts) and Map.has_key?(base_map, k) ->
          {acc, pr}

        Map.has_key?(base_map, k) ->
          {mv, pr2} = merge_value(Map.fetch!(base_map, k), ov, name, kpath, pr, opts)
          {Map.put(acc, k, mv), pr2}

        true ->
          {Map.put(acc, k, ov), leaf_provenance(ov, name, kpath, pr)}
      end
    end)
  end

  defp merge_value(bv, ov, name, kpath, pr, opts) do
    cond do
      is_map(bv) and is_map(ov) ->
        merge_map(bv, ov, name, kpath, pr, opts)

      is_list(bv) and is_list(ov) ->
        case list_strategy_for(kpath, opts) do
          :replace ->
            {ov, Map.put(pr, kpath, name)}

          :append ->
            names = List.wrap(Map.get(pr, kpath)) ++ [name]
            {bv ++ ov, Map.put(pr, kpath, names)}
        end

      is_map(ov) ->
        # Override replaces a scalar/list with a whole subtree.
        {ov, leaf_provenance(ov, name, kpath, prune_subtree(pr, kpath))}

      true ->
        # Override replaces whatever was there (possibly a subtree) with a leaf.
        {ov, Map.put(prune_subtree(pr, kpath), kpath, name)}
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp leaf_provenance(value, name, path, pr) when is_map(value) do
    Enum.reduce(value, pr, fn {k, v}, acc -> leaf_provenance(v, name, path ++ [k], acc) end)
  end

  defp leaf_provenance(_value, name, path, pr), do: Map.put(pr, path, name)

  # Drops `kpath` and every provenance entry nested beneath it, so a subtree that a
  # higher layer replaced leaves no stale descendant paths behind.
  defp prune_subtree(pr, kpath) do
    depth = length(kpath)

    Map.reject(pr, fn {path, _name} ->
      is_list(path) and Enum.take(path, depth) == kpath
    end)
  end

  defp locked?(kpath, %{locked_paths: locked}), do: kpath in locked

  defp list_strategy_for(kpath, %{per_key_strategies: per_key, global_list_strategy: global}) do
    Map.get(per_key, kpath, global)
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule LayeredConfigTest do
  use ExUnit.Case, async: false

  # -------------------------------------------------------
  # Basic scalar layering + provenance
  # -------------------------------------------------------

  test "single layer returns config unchanged with self provenance" do
    result = LayeredConfig.merge([{:base, %{a: 1, b: %{c: 2}}}])

    assert result.config == %{a: 1, b: %{c: 2}}
    assert result.provenance[[:a]] == :base
    assert result.provenance[[:b, :c]] == :base
  end

  test "later layer overrides scalar and records provenance" do
    # TODO
  end

  test "three layers apply in increasing precedence" do
    layers = [
      {:default, %{level: :info, retries: 1}},
      {:file, %{level: :warn}},
      {:env, %{retries: 5}}
    ]

    result = LayeredConfig.merge(layers)

    assert result.config == %{level: :warn, retries: 5}
    assert result.provenance[[:level]] == :file
    assert result.provenance[[:retries]] == :env
  end

  # -------------------------------------------------------
  # Deep merge
  # -------------------------------------------------------

  test "nested map is deep-merged across layers with per-leaf provenance" do
    layers = [
      {:base, %{db: %{host: "localhost", port: 5432, name: "prod"}}},
      {:override, %{db: %{port: 5433}}}
    ]

    result = LayeredConfig.merge(layers)

    assert result.config.db == %{host: "localhost", port: 5433, name: "prod"}
    assert result.provenance[[:db, :host]] == :base
    assert result.provenance[[:db, :port]] == :override
    assert result.provenance[[:db, :name]] == :base
  end

  test "keys introduced by a higher layer get that layer's provenance" do
    layers = [{:base, %{a: 1}}, {:extra, %{b: %{c: 3}}}]

    result = LayeredConfig.merge(layers)

    assert result.config == %{a: 1, b: %{c: 3}}
    assert result.provenance[[:a]] == :base
    assert result.provenance[[:b, :c]] == :extra
  end

  # -------------------------------------------------------
  # List strategies
  # -------------------------------------------------------

  test "lists are replaced by default" do
    layers = [{:base, %{tags: ["a", "b"]}}, {:env, %{tags: ["x"]}}]

    result = LayeredConfig.merge(layers)

    assert result.config.tags == ["x"]
    assert result.provenance[[:tags]] == :env
  end

  test "append strategy concatenates and provenance is a list of layer names" do
    layers = [{:base, %{tags: ["a"]}}, {:env, %{tags: ["b"]}}]

    result = LayeredConfig.merge(layers, list_strategy: :append)

    assert result.config.tags == ["a", "b"]
    assert result.provenance[[:tags]] == [:base, :env]
  end

  test "append across three layers accumulates provenance in order" do
    layers = [
      {:base, %{plugins: ["core"]}},
      {:file, %{plugins: ["auth"]}},
      {:env, %{plugins: ["metrics"]}}
    ]

    result = LayeredConfig.merge(layers, list_strategy: :append)

    assert result.config.plugins == ["core", "auth", "metrics"]
    assert result.provenance[[:plugins]] == [:base, :file, :env]
  end

  test "per-key list strategy overrides the global strategy" do
    layers = [
      {:base, %{tags: ["a"], plugins: ["core"]}},
      {:env, %{tags: ["b"], plugins: ["extra"]}}
    ]

    result =
      LayeredConfig.merge(layers,
        list_strategy: :replace,
        list_strategies: %{[:tags] => :append}
      )

    assert result.config.tags == ["a", "b"]
    assert result.config.plugins == ["extra"]
    assert result.provenance[[:tags]] == [:base, :env]
    assert result.provenance[[:plugins]] == :env
  end

  # -------------------------------------------------------
  # Locked keys
  # -------------------------------------------------------

  test "locked key preserves the earlier value and provenance" do
    layers = [
      {:base, %{secret: "s3cr3t", other: "base"}},
      {:env, %{secret: "pwned", other: "new"}}
    ]

    result = LayeredConfig.merge(layers, locked: [[:secret]])

    assert result.config.secret == "s3cr3t"
    assert result.config.other == "new"
    assert result.provenance[[:secret]] == :base
    assert result.provenance[[:other]] == :env
  end

  test "locked nested key is preserved while siblings merge" do
    layers = [
      {:base, %{db: %{password: "keep", host: "localhost"}}},
      {:env, %{db: %{password: "hack", host: "evil.host"}}}
    ]

    result = LayeredConfig.merge(layers, locked: [[:db, :password]])

    assert result.config.db.password == "keep"
    assert result.config.db.host == "evil.host"
    assert result.provenance[[:db, :password]] == :base
    assert result.provenance[[:db, :host]] == :env
  end

  test "locking one path does not protect the same key elsewhere" do
    layers = [
      {:base, %{primary: %{token: "real"}, secondary: %{token: "also_real"}}},
      {:env, %{primary: %{token: "fake"}, secondary: %{token: "replaced"}}}
    ]

    result = LayeredConfig.merge(layers, locked: [[:primary, :token]])

    assert result.config.primary.token == "real"
    assert result.config.secondary.token == "replaced"
  end

  # -------------------------------------------------------
  # Errors
  # -------------------------------------------------------

  test "empty layer list raises ArgumentError" do
    assert_raise ArgumentError, fn -> LayeredConfig.merge([]) end
  end

  test "provenance drops paths whose subtree a higher layer replaced with a scalar" do
    layers = [
      {:base, %{db: %{host: "localhost", port: 5432}}},
      {:env, %{db: "disabled"}}
    ]

    result = LayeredConfig.merge(layers)

    assert result.config == %{db: "disabled"}
    assert result.provenance[[:db]] == :env
    refute Map.has_key?(result.provenance, [:db, :host])
    refute Map.has_key?(result.provenance, [:db, :port])
  end

  test "locked path absent from earlier layers may still be set by a higher layer" do
    layers = [
      {:base, %{db: %{host: "localhost"}}},
      {:env, %{db: %{password: "fresh"}, token: "new"}}
    ]

    result = LayeredConfig.merge(layers, locked: [[:db, :password], [:token]])

    assert result.config.db.password == "fresh"
    assert result.config.token == "new"
    assert result.provenance[[:db, :password]] == :env
    assert result.provenance[[:token]] == :env
  end

  test "per-key replace overrides a global append strategy" do
    layers = [
      {:base, %{tags: ["a"], plugins: ["core"]}},
      {:env, %{tags: ["b"], plugins: ["extra"]}}
    ]

    result =
      LayeredConfig.merge(layers,
        list_strategy: :append,
        list_strategies: %{[:tags] => :replace}
      )

    assert result.config.tags == ["b"]
    assert result.config.plugins == ["core", "extra"]
    assert result.provenance[[:tags]] == :env
    assert result.provenance[[:plugins]] == [:base, :env]
  end

  test "tuple key paths work for locked and list_strategies options" do
    layers = [
      {:base, %{db: %{password: "keep", tags: ["a"]}}},
      {:env, %{db: %{password: "hack", tags: ["b"]}}}
    ]

    result =
      LayeredConfig.merge(layers,
        locked: [{:db, :password}],
        list_strategies: %{{:db, :tags} => :append}
      )

    assert result.config.db.password == "keep"
    assert result.config.db.tags == ["a", "b"]
    assert result.provenance[[:db, :password]] == :base
    assert result.provenance[[:db, :tags]] == [:base, :env]
  end

  test "append provenance omits a middle layer that contributed no elements" do
    layers = [
      {:base, %{plugins: ["core"]}},
      {:file, %{other: 1}},
      {:env, %{plugins: ["metrics"]}}
    ]

    result = LayeredConfig.merge(layers, list_strategy: :append)

    assert result.config.plugins == ["core", "metrics"]
    assert result.provenance[[:plugins]] == [:base, :env]
    assert result.provenance[[:other]] == :file
  end

  test "merge result exposes exactly the config and provenance keys" do
    result = LayeredConfig.merge([{:base, %{a: 1}}, {:env, %{a: 2}}])

    assert result |> Map.keys() |> Enum.sort() == [:config, :provenance]
    assert map_size(result) == 2
  end

  # -------------------------------------------------------
  # Append with a single contributing layer
  # -------------------------------------------------------

  # Under :append the contributors of a list leaf are exactly the layers that set a
  # list at that path, in precedence order; a layer that sets no list there is never
  # named, including when only one layer contributes at all. The provenance is read
  # through List.wrap/1 so a lone contributor is accepted either as its bare name or
  # as a one-element list of names -- what is pinned is *which* layers are named.
  test "append names only the single contributing layer, never the silent ones" do
    lower_only = [
      {:base, %{plugins: ["core"]}},
      {:file, %{other: 1}},
      {:env, %{unrelated: true}}
    ]

    result = LayeredConfig.merge(lower_only, list_strategy: :append)

    assert result.config.plugins == ["core"]
    assert List.wrap(result.provenance[[:plugins]]) == [:base]

    higher_only = [
      {:base, %{db: %{host: "localhost"}}},
      {:file, %{db: %{port: 5432}}},
      {:env, %{db: %{tags: ["metrics"]}}}
    ]

    nested = LayeredConfig.merge(higher_only, list_strategy: :append)

    assert nested.config.db.tags == ["metrics"]
    assert List.wrap(nested.provenance[[:db, :tags]]) == [:env]
  end
end
```
