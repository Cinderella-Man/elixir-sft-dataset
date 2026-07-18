# Bring this working module up to house style

I asked for the following:

Write me an Elixir module called `StrictConfigMerger` that deep-merges two
configuration maps but, instead of silently letting the override win everywhere,
**detects conflicts** and reports them.

One primary public function:
- `StrictConfigMerger.merge(base_config, override_config, opts \\ [])` returning
  either `{:ok, merged_map}` when there are no conflicts, or
  `{:error, conflicts}` where `conflicts` is a list of conflict maps sorted by their
  key-path.

Deep-merge rules (as usual):
- Nested maps are deep-merged, not replaced wholesale.
- Scalars from `override_config` replace those in `base_config` at the same path.
- Lists follow the `:list_strategy` option: `:replace` (default) or `:append`.

Conflict detection is governed by these options:
- `:strict` (boolean, default `false`). When `true`, if both maps hold a value at the
  same key-path whose **types differ** — different scalar kinds (e.g. integer vs
  string), or a structural mismatch such as map-vs-scalar or list-vs-scalar — that is
  a `:type_mismatch` conflict. When `false`, such cases just let the override win with
  no conflict. Two maps, or two lists, are never a type mismatch (they merge per the
  rules above).
- `:locked` — a list of key-path tuples/lists. If `override_config` supplies a
  **different** value at a locked path (where the base already has a value), that is
  always a `:locked_violation` conflict, regardless of `:strict`. Supplying the same
  value, or not touching the path, is fine.
- `:required` — a list of key-path tuples/lists that must be present in the merged
  result. Any missing one is a `:missing_required` conflict.

Each conflict is a map with at least `:type` (`:type_mismatch` | `:locked_violation` |
`:missing_required`) and `:path` (a list of atoms). Type-mismatch and locked-violation
conflicts should also include `:base` and `:override` values. When conflicts exist,
return `{:error, conflicts_sorted_by_path}` and do not return a merged map. Key paths
in `:locked`, `:required`, and `:list_strategies`-style options are lists or tuples of
atoms.

Give me the complete module in a single file. Use only the Elixir standard library.

Here is my implementation. It compiles and passes every test — the behavior
is correct — but it was rejected by the style review:

```elixir
defmodule StrictConfigMerger do
  @moduledoc """
  Deep-merges two configuration maps while detecting conflicts.

  Returns `{:ok, merged}` when no conflicts are found, otherwise `{:error, conflicts}`
  with the conflicts sorted by key-path. Conflict kinds:

    * `:type_mismatch` (only when `:strict` is `true`) — both sides hold values of
      differing kinds at the same path.
    * `:locked_violation` — an override changes a `:locked` path's value.
    * `:missing_required` — a `:required` path is absent from the merged result.
  """

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @spec merge(map(), map(), keyword()) :: {:ok, map()} | {:error, [map()]}
  def merge(base_config, override_config, opts \\ [])
      when is_map(base_config) and is_map(override_config) do
    resolved = resolve_opts(opts)

    {merged, conflicts} = do_merge(base_config, override_config, [], resolved)

    missing =
      for path <- resolved.required, not path_present?(merged, path) do
        %{type: :missing_required, path: path}
      end

    all = conflicts ++ missing

    case all do
      [] -> {:ok, merged}
      _ -> {:error, Enum.sort_by(all, & &1.path)}
    end
  end

  # ---------------------------------------------------------------------------
  # Recursive merge collecting conflicts
  # ---------------------------------------------------------------------------

  defp do_merge(base, over, path, opts) when is_map(base) and is_map(over) do
    keys = Enum.uniq(Map.keys(base) ++ Map.keys(over))

    Enum.reduce(keys, {%{}, []}, fn k, {acc, conf} ->
      kpath = path ++ [k]

      cond do
        not Map.has_key?(over, k) ->
          {Map.put(acc, k, Map.fetch!(base, k)), conf}

        not Map.has_key?(base, k) ->
          {Map.put(acc, k, Map.fetch!(over, k)), conf}

        true ->
          {value, new_conf} =
            merge_value(Map.fetch!(base, k), Map.fetch!(over, k), kpath, opts)

          {Map.put(acc, k, value), conf ++ new_conf}
      end
    end)
  end

  defp merge_value(bv, ov, kpath, opts) do
    cond do
      locked?(kpath, opts) and bv != ov ->
        {bv, [%{type: :locked_violation, path: kpath, base: bv, override: ov}]}

      locked?(kpath, opts) ->
        {bv, []}

      is_map(bv) and is_map(ov) ->
        do_merge(bv, ov, kpath, opts)

      is_list(bv) and is_list(ov) ->
        case list_strategy_for(kpath, opts) do
          :replace -> {ov, []}
          :append -> {bv ++ ov, []}
        end

      opts.strict and type_kind(bv) != type_kind(ov) ->
        {ov, [%{type: :type_mismatch, path: kpath, base: bv, override: ov}]}

      true ->
        {ov, []}
    end
  end

  # ---------------------------------------------------------------------------
  # Options + helpers
  # ---------------------------------------------------------------------------

  defp resolve_opts(opts) do
    per_key =
      opts
      |> Keyword.get(:list_strategies, %{})
      |> Map.new(fn {path, strat} -> {normalise_path(path), strat} end)

    %{
      strict: Keyword.get(opts, :strict, false),
      global_list_strategy: Keyword.get(opts, :list_strategy, :replace),
      per_key_strategies: per_key,
      locked_paths: Enum.map(Keyword.get(opts, :locked, []), &normalise_path/1),
      required: Enum.map(Keyword.get(opts, :required, []), &normalise_path/1)
    }
  end

  defp normalise_path(path) when is_list(path), do: path
  defp normalise_path(path) when is_tuple(path), do: Tuple.to_list(path)

  defp locked?(kpath, %{locked_paths: locked}), do: kpath in locked

  defp list_strategy_for(kpath, %{per_key_strategies: per_key, global_list_strategy: global}) do
    Map.get(per_key, kpath, global)
  end

  defp path_present?(_map, []), do: true

  defp path_present?(map, [k | rest]) when is_map(map) do
    case Map.fetch(map, k) do
      {:ok, v} -> path_present?(v, rest)
      :error -> false
    end
  end

  defp path_present?(_map, _path), do: false

  defp type_kind(v) when is_integer(v), do: :integer
  defp type_kind(v) when is_float(v), do: :float
  defp type_kind(v) when is_boolean(v), do: :boolean
  defp type_kind(v) when is_atom(v), do: :atom
  defp type_kind(v) when is_binary(v), do: :binary
  defp type_kind(v) when is_list(v), do: :list
  defp type_kind(v) when is_map(v), do: :map
  defp type_kind(_v), do: :other
end
```

The style review said:

```
The solution is green but does not meet the house style: no @doc on any public function. Fix solution.ex so it has a `@moduledoc`, an `@spec` and `@doc` on public functions, no `TODO` markers, and compiles with ZERO warnings. Keep the behavior identical and do not weaken test_harness.exs.
```

Fix every finding in the review WITHOUT changing any behavior: the module
must keep passing exactly the tests it passes now. Give me the complete
corrected module in a single file.
<!-- minted from logs/attempts/040_004_conflict_detecting_strict_config_merger_01/attempt_0 -->
