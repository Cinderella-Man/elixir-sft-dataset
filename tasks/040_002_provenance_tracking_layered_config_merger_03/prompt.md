# Fill in the middle: `LayeredConfig.merge_map/6`

`LayeredConfig` merges an ordered stack of named configuration layers (given in
increasing precedence order) into a single effective configuration and reports the
provenance of every effective value. The whole module is provided below with the
body of the private `merge_map/6` function removed. Your job is to implement only
that function.

## What `merge_map/6` must do

Implement the private `merge_map(base_map, over_map, name, path, prov, opts)`
function. It deep-merges the higher-precedence layer `over_map` (whose layer name is
`name`) onto the already-accumulated `base_map`, while threading the provenance map
`prov` through the whole traversal. `path` is the key-path (a list of atoms from the
root) at which `base_map`/`over_map` currently sit, and `opts` is the resolved
options map (`%{global_list_strategy:, per_key_strategies:, locked_paths:}`).

It must return a `{merged_map, updated_provenance}` tuple, produced by reducing over
the key/value pairs of `over_map` starting from the accumulator `{base_map, prov}`.
For each `{k, ov}` pair in `over_map`, compute the current key-path
`kpath = path ++ [k]` and handle three cases:

  * **Locked and already present** — if `kpath` is locked (use `locked?/2`) *and*
    `base_map` already has key `k`, the earlier layer wins: leave both the
    accumulated map and provenance unchanged.

  * **Key already present (not locked)** — merge the existing base value with the
    override value by delegating to `merge_value/6` (passing the base value fetched
    from `base_map`, `ov`, `name`, `kpath`, the current provenance, and `opts`).
    Put the merged value under `k` in the accumulator and carry forward the
    provenance `merge_value/6` returns.

  * **New key** — the key does not exist in `base_map`: insert `ov` under `k` in the
    accumulator, and record provenance for it (and, if `ov` is a map, for all of its
    nested leaves) via `leaf_provenance/4` with `name`, `kpath`, and the current
    provenance.

The result of the reduction — the `{map, provenance}` accumulator — is the function's
return value.

## Module

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
    # TODO
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