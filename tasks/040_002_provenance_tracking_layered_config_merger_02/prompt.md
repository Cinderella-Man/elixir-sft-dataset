Implement the private `merge_value/6` function.

`merge_value(base_value, over_value, name, kpath, prov, opts)` merges a single
base value with the corresponding override value coming from the layer `name` at
the key-path `kpath` (a list of atoms from the root). It threads the provenance
map `prov` through and returns a `{merged_value, updated_provenance}` tuple.

It must handle the following cases:

  * **Both values are maps** — recurse into them with `merge_map/6` (passing the
    same `name`, `kpath`, `prov`, and `opts`) so nested maps are deep-merged rather
    than replaced.
  * **Both values are lists** — consult `list_strategy_for/2` for `kpath`:
    * `:replace` — the override list wins; record `name` as the provenance for
      `kpath`.
    * `:append` — concatenate the override list onto the base list (`base ++ over`);
      the provenance for `kpath` becomes the ordered list of contributing layer
      names, i.e. the existing provenance value (wrapped with `List.wrap/1`) with
      `name` appended.
  * **Only the override is a map** (it replaces a scalar or list with a whole
    subtree) — take the override value and rebuild the leaf provenance for that
    subtree with `leaf_provenance/4`, first removing any stale entry stored directly
    at `kpath` (`Map.delete(prov, kpath)`).
  * **Otherwise** (scalar override wins over any other base) — the override value
    wins and `name` is recorded as the provenance for `kpath`.

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
    # TODO
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