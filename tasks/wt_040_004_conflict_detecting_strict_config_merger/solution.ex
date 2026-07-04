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

  @doc """
  Deep-merges `override_config` onto `base_config`, detecting conflicts.

  Supported `opts`:

    * `:strict` (boolean, default `false`) — flag differing value kinds at the same
      path as `:type_mismatch` conflicts.
    * `:list_strategy` (`:replace` | `:append`, default `:replace`) — how lists at the
      same path combine.
    * `:list_strategies` — a map of key-path (list/tuple of atoms) to a per-path list
      strategy overriding the global one.
    * `:locked` — a list of key-paths that must keep their base value.
    * `:required` — a list of key-paths that must be present in the merged result.

  Returns `{:ok, merged_map}` when there are no conflicts, or `{:error, conflicts}`
  where `conflicts` is a list of conflict maps sorted by their key-path.
  """
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