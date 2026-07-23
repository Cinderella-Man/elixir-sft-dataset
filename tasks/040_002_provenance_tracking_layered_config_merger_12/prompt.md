# Implement the missing function

Below you'll find a task's full specification, then a working, tested
solution with one gap: `merge` — every clause body swapped for
`# TODO`. Rebuild exactly that function so the module passes the task's
whole suite again, and leave every other line precisely as shown.

## The task

Write me an Elixir module called `LayeredConfig` that merges an ordered stack of
named configuration layers into a single effective configuration **and reports the
provenance** of every effective value (which layer it came from).

I need one primary public function:
- `LayeredConfig.merge(layers, opts \\ [])` where `layers` is a non-empty list of
  `{layer_name, config_map}` tuples given in **increasing precedence order** (the
  first tuple is the base, each later layer overrides the ones before it).

It must return a map with exactly two keys:
- `:config` — the deep-merged effective configuration map.
- `:provenance` — a map from **key-path** (a list of atoms from root to a leaf,
  e.g. `[:db, :port]`) to the name of the layer that supplied the winning value.

The merging rules:
- **Deep merging**: if two layers both hold a map at the same key, recurse into it
  rather than replacing the whole map.
- **Later layers win** for scalars (strings, integers, atoms, booleans): the value
  from the highest-precedence layer that set the leaf wins, and provenance records
  that layer's name.
- **Subtree replaced by a leaf**: when a higher layer overrides an entire subtree
  (a map in a lower layer) with a scalar or list, the winning value replaces the
  whole subtree, provenance records the new leaf path pointing at that layer, and
  every provenance entry for paths nested beneath the replaced subtree is dropped.
- **List strategy**: controlled by the `:list_strategy` option, either `:replace`
  (default, higher layer's list wins) or `:append` (higher layer's list is
  concatenated onto the accumulated list). For an appended leaf, its provenance is
  the **list of layer names** (in precedence order) that contributed elements —
  layers that set no list at that path are omitted from the list.
- **Per-key list strategy**: the `:list_strategies` option accepts a map of
  `key_path => :replace | :append` (key paths as lists or tuples of atoms) that
  overrides the global `:list_strategy` for those specific paths.
- **Locked keys**: the `:locked` option accepts a list of key-path tuples/lists.
  When a locked path already exists in a lower-precedence layer, higher layers must
  not change it — the earlier value and its provenance are preserved. Locking only
  applies where the key already exists in an earlier layer.

Key paths for `:list_strategies` and `:locked` are lists (or tuples) of atoms from
root to the target key.

A single-layer stack must return that layer's config unchanged with every leaf's
provenance pointing at that one layer. Raise `ArgumentError` on an empty layer list.

Give me the complete module in a single file. Use only the Elixir standard library.

## The module with `merge` missing

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

  def merge(layers, opts \\ []) when is_list(layers) do
    # TODO
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

Reply with `merge` alone (bring along any `@doc`/`@spec`/`@impl` lines
that belong directly above it) — just the function, never the whole
module.
