defmodule StrictConfigMerger do
  @moduledoc """
  Deep-merges two configuration maps while detecting and reporting conflicts.

  Unlike a plain `Map.merge/3`-style deep merge, where the override silently wins
  everywhere, this module can flag disagreements between the two configurations and
  refuse to produce a merged result when any are found.

  ## Merge rules

    * Nested maps are deep-merged rather than replaced wholesale.
    * Scalars from the override replace those in the base at the same key path.
    * Lists follow the `:list_strategy` option — `:replace` (default) or `:append`.

  ## Options

    * `:strict` — boolean, defaults to `false`. When `true`, a value present in both
      configurations at the same path whose type differs (integer vs string, map vs
      scalar, list vs scalar, ...) produces a `:type_mismatch` conflict. Two maps, or
      two lists, are never a type mismatch — they merge per the rules above.
    * `:locked` — a list of key paths (lists or tuples of atoms). If the override
      supplies a *different* value at a locked path where the base already has a
      value, that is a `:locked_violation` conflict, regardless of `:strict`.
    * `:required` — a list of key paths that must be present in the merged result.
      Any missing path is a `:missing_required` conflict.
    * `:list_strategy` — `:replace` (default) or `:append`.

  ## Result

  `merge/3` returns `{:ok, merged_map}` when no conflicts are detected, or
  `{:error, conflicts}` where `conflicts` is a list of conflict maps sorted by their
  `:path`. Each conflict map carries at least `:type` and `:path`; `:type_mismatch`
  and `:locked_violation` conflicts also carry `:base` and `:override`.

  ## Examples

      iex> StrictConfigMerger.merge(%{db: %{host: "a", port: 1}}, %{db: %{port: 2}})
      {:ok, %{db: %{host: "a", port: 2}}}

      iex> StrictConfigMerger.merge(%{port: 1}, %{port: "2"}, strict: true)
      {:error, [%{type: :type_mismatch, path: [:port], base: 1, override: "2"}]}

  """

  @type path :: [atom()]
  @type config :: map()
  @type conflict :: %{required(:type) => conflict_type, required(:path) => path, optional(any) => any}
  @type conflict_type :: :type_mismatch | :locked_violation | :missing_required
  @type list_strategy :: :replace | :append

  @doc """
  Deep-merges `override_config` into `base_config`, detecting conflicts.

  Returns `{:ok, merged}` when no conflicts are found, otherwise `{:error, conflicts}`
  with the conflicts sorted by key path. See the module documentation for the full set
  of supported options (`:strict`, `:locked`, `:required` and `:list_strategy`).

  ## Examples

      iex> StrictConfigMerger.merge(%{a: %{b: 1}}, %{a: %{c: 2}})
      {:ok, %{a: %{b: 1, c: 2}}}

      iex> StrictConfigMerger.merge(%{a: 1}, %{a: 2}, locked: [[:a]])
      {:error, [%{type: :locked_violation, path: [:a], base: 1, override: 2}]}

  """
  @spec merge(config, config, keyword) :: {:ok, config} | {:error, [conflict]}
  def merge(base_config, override_config, opts \\ [])
      when is_map(base_config) and is_map(override_config) and is_list(opts) do
    strict? = Keyword.get(opts, :strict, false)
    list_strategy = normalize_list_strategy(Keyword.get(opts, :list_strategy, :replace))
    locked = opts |> Keyword.get(:locked, []) |> normalize_paths()
    required = opts |> Keyword.get(:required, []) |> normalize_paths()

    {merged, conflicts} =
      deep_merge(base_config, override_config, [], %{
        strict?: strict?,
        list_strategy: list_strategy,
        locked: locked
      })

    conflicts = conflicts ++ missing_required_conflicts(merged, required)

    case sort_conflicts(conflicts) do
      [] -> {:ok, merged}
      sorted -> {:error, sorted}
    end
  end

  # -- merging ---------------------------------------------------------------------

  @spec deep_merge(map, map, path, map) :: {map, [conflict]}
  defp deep_merge(base, override, path, ctx) do
    override
    |> Map.keys()
    |> Enum.reduce({base, []}, fn key, {acc, conflicts} ->
      child_path = path ++ [key]
      override_value = Map.fetch!(override, key)

      case Map.fetch(base, key) do
        :error ->
          {Map.put(acc, key, override_value), conflicts}

        {:ok, base_value} ->
          {value, new_conflicts} = merge_value(base_value, override_value, child_path, ctx)
          {Map.put(acc, key, value), conflicts ++ new_conflicts}
      end
    end)
  end

  @spec merge_value(any, any, path, map) :: {any, [conflict]}
  defp merge_value(base_value, override_value, path, ctx) do
    locked_conflicts = locked_conflicts(base_value, override_value, path, ctx)

    {value, conflicts} = do_merge_value(base_value, override_value, path, ctx)

    {value, locked_conflicts ++ conflicts}
  end

  @spec do_merge_value(any, any, path, map) :: {any, [conflict]}
  defp do_merge_value(base_value, override_value, path, ctx)
       when is_map(base_value) and is_map(override_value) do
    deep_merge(base_value, override_value, path, ctx)
  end

  defp do_merge_value(base_value, override_value, _path, ctx)
       when is_list(base_value) and is_list(override_value) do
    case ctx.list_strategy do
      :append -> {base_value ++ override_value, []}
      :replace -> {override_value, []}
    end
  end

  defp do_merge_value(base_value, override_value, path, ctx) do
    if ctx.strict? and type_mismatch?(base_value, override_value) do
      {override_value,
       [%{type: :type_mismatch, path: path, base: base_value, override: override_value}]}
    else
      {override_value, []}
    end
  end

  # -- conflict detection ----------------------------------------------------------

  @spec locked_conflicts(any, any, path, map) :: [conflict]
  defp locked_conflicts(base_value, override_value, path, ctx) do
    if path in ctx.locked and not equal?(base_value, override_value) do
      [%{type: :locked_violation, path: path, base: base_value, override: override_value}]
    else
      []
    end
  end

  @spec missing_required_conflicts(map, [path]) :: [conflict]
  defp missing_required_conflicts(merged, required) do
    required
    |> Enum.reject(&path_present?(merged, &1))
    |> Enum.map(&%{type: :missing_required, path: &1})
  end

  @spec path_present?(any, path) :: boolean
  defp path_present?(_value, []), do: true

  defp path_present?(value, [key | rest]) when is_map(value) do
    case Map.fetch(value, key) do
      {:ok, child} -> path_present?(child, rest)
      :error -> false
    end
  end

  defp path_present?(_value, _path), do: false

  # -- type classification ---------------------------------------------------------

  @spec type_mismatch?(any, any) :: boolean
  defp type_mismatch?(base_value, override_value) do
    type_of(base_value) != type_of(override_value)
  end

  @spec type_of(any) :: atom
  defp type_of(value) when is_map(value), do: :map
  defp type_of(value) when is_list(value), do: :list
  defp type_of(value) when is_boolean(value), do: :boolean
  defp type_of(value) when is_atom(value), do: :atom
  defp type_of(value) when is_integer(value), do: :integer
  defp type_of(value) when is_float(value), do: :float
  defp type_of(value) when is_binary(value), do: :binary
  defp type_of(value) when is_tuple(value), do: :tuple
  defp type_of(value) when is_function(value), do: :function
  defp type_of(value) when is_pid(value), do: :pid
  defp type_of(value) when is_reference(value), do: :reference
  defp type_of(value) when is_port(value), do: :port
  defp type_of(_value), do: :unknown

  # -- helpers ---------------------------------------------------------------------

  @spec equal?(any, any) :: boolean
  defp equal?(+0.0, +0.0), do: true
  defp equal?(-0.0, -0.0), do: true
  defp equal?(base_value, override_value), do: base_value === override_value

  @spec normalize_list_strategy(any) :: list_strategy
  defp normalize_list_strategy(:append), do: :append
  defp normalize_list_strategy(_other), do: :replace

  @spec normalize_paths(any) :: [path]
  defp normalize_paths(paths) when is_list(paths), do: Enum.map(paths, &normalize_path/1)
  defp normalize_paths(_paths), do: []

  @spec normalize_path(any) :: path
  defp normalize_path(path) when is_tuple(path), do: Tuple.to_list(path)
  defp normalize_path(path) when is_list(path), do: path
  defp normalize_path(path) when is_atom(path), do: [path]

  @spec sort_conflicts([conflict]) :: [conflict]
  defp sort_conflicts(conflicts) do
    Enum.sort_by(conflicts, &{&1.path, conflict_rank(&1.type)})
  end

  @spec conflict_rank(conflict_type) :: non_neg_integer
  defp conflict_rank(:locked_violation), do: 0
  defp conflict_rank(:type_mismatch), do: 1
  defp conflict_rank(:missing_required), do: 2
end