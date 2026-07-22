defmodule ConfigMerger do
  @moduledoc """
  Deep-merges configuration maps with a configurable override strategy.

  The core entry point is `merge/3`, which combines a base configuration map with an
  override configuration map. By default, later sources win: scalar values found in the
  override replace their counterparts in the base at the same key path. When both sides
  hold a map at the same key, the maps are merged recursively rather than replaced
  wholesale.

  Lists are handled by a strategy that can be tuned globally or per key path:

    * `:list_strategy` — `:replace` (default) or `:append`, applied to every list;
    * `:list_strategies` — a map of key path to strategy, taking precedence over the
      global strategy for the listed paths;
    * `:locked` — a list of key paths whose base values must never be overridden.

  A *key path* is the list of atoms naming the nesting from the root of the configuration
  down to the target key. For example, `[:database, :password]` refers to the `:password`
  key nested inside the map stored under `:database`. Paths are matched in full, so
  locking `[:database, :password]` leaves `[:cache, :password]` untouched.

  ## Examples

      iex> base = %{host: "localhost", pools: [1, 2], db: %{user: "root", password: "s3cr3t"}}
      iex> override = %{host: "example.com", pools: [3], db: %{user: "app", password: "nope"}}
      iex> ConfigMerger.merge(base, override,
      ...>   list_strategy: :append,
      ...>   locked: [[:db, :password]]
      ...> )
      %{host: "example.com", pools: [1, 2, 3], db: %{user: "app", password: "s3cr3t"}}
  """

  @type key_path :: [atom()]
  @type list_strategy :: :replace | :append
  @type opt ::
          {:list_strategy, list_strategy()}
          | {:list_strategies, %{optional(key_path()) => list_strategy()}}
          | {:locked, [key_path()]}
  @type opts :: [opt()]

  @default_list_strategy :replace

  @doc """
  Deep-merges `override_config` into `base_config` and returns the merged map.

  Scalar values in `override_config` win over those in `base_config`. Nested maps present
  on both sides are merged recursively. Lists are combined according to the configured
  list strategy, and keys whose full path appears in `:locked` keep their base value.

  ## Options

    * `:list_strategy` — the global list strategy, either `:replace` (the default, where
      the override list wins outright) or `:append` (where the override list is appended
      to the base list).
    * `:list_strategies` — a map of key path to `:replace` / `:append`, overriding the
      global strategy for those exact paths.
    * `:locked` — a list of key paths that must retain their base value. A locked path
      that is absent from the base but present in the override is simply dropped.

  ## Examples

      iex> ConfigMerger.merge(%{a: 1, b: %{c: 2}}, %{b: %{c: 3, d: 4}})
      %{a: 1, b: %{c: 3, d: 4}}

      iex> ConfigMerger.merge(%{tags: ["a"]}, %{tags: ["b"]}, list_strategy: :append)
      %{tags: ["a", "b"]}

      iex> ConfigMerger.merge(
      ...>   %{s: %{hosts: ["a"]}, t: ["x"]},
      ...>   %{s: %{hosts: ["b"]}, t: ["y"]},
      ...>   list_strategy: :append,
      ...>   list_strategies: %{[:s, :hosts] => :replace}
      ...> )
      %{s: %{hosts: ["b"]}, t: ["x", "y"]}

      iex> ConfigMerger.merge(%{db: %{password: "keep"}}, %{db: %{password: "drop"}},
      ...>   locked: [[:db, :password]]
      ...> )
      %{db: %{password: "keep"}}
  """
  @spec merge(map(), map(), opts()) :: map()
  def merge(base_config, override_config, opts \\ [])
      when is_map(base_config) and is_map(override_config) and is_list(opts) do
    settings = build_settings(opts)
    do_merge(base_config, override_config, [], settings)
  end

  # -- internals -------------------------------------------------------------------

  @spec build_settings(opts()) :: map()
  defp build_settings(opts) do
    %{
      list_strategy: normalize_strategy(Keyword.get(opts, :list_strategy, @default_list_strategy)),
      list_strategies: normalize_strategies(Keyword.get(opts, :list_strategies, %{})),
      locked: normalize_locked(Keyword.get(opts, :locked, []))
    }
  end

  @spec normalize_strategy(term()) :: list_strategy()
  defp normalize_strategy(:append), do: :append
  defp normalize_strategy(:replace), do: :replace
  defp normalize_strategy(other), do: raise(ArgumentError, "invalid list strategy: #{inspect(other)}")

  @spec normalize_strategies(term()) :: %{optional(key_path()) => list_strategy()}
  defp normalize_strategies(strategies) when is_map(strategies) do
    Map.new(strategies, fn {path, strategy} ->
      {normalize_path(path), normalize_strategy(strategy)}
    end)
  end

  defp normalize_strategies(strategies) when is_list(strategies) do
    strategies |> Map.new() |> normalize_strategies()
  end

  @spec normalize_locked(term()) :: MapSet.t(key_path())
  defp normalize_locked(locked) when is_list(locked) do
    locked |> Enum.map(&normalize_path/1) |> MapSet.new()
  end

  # A bare key (not wrapped in a list) is treated as a root-level path for convenience.
  @spec normalize_path(term()) :: key_path()
  defp normalize_path(path) when is_list(path), do: path
  defp normalize_path(key), do: [key]

  @spec do_merge(map(), map(), key_path(), map()) :: map()
  defp do_merge(base, override, path, settings) do
    Enum.reduce(override, base, fn {key, override_value}, acc ->
      key_path = path ++ [key]

      cond do
        locked?(key_path, settings) ->
          acc

        Map.has_key?(acc, key) ->
          merged = merge_values(Map.fetch!(acc, key), override_value, key_path, settings)
          Map.put(acc, key, merged)

        true ->
          Map.put(acc, key, override_value)
      end
    end)
  end

  @spec merge_values(term(), term(), key_path(), map()) :: term()
  defp merge_values(base_value, override_value, key_path, settings)
       when is_map(base_value) and is_map(override_value) do
    if struct?(base_value) or struct?(override_value) do
      override_value
    else
      do_merge(base_value, override_value, key_path, settings)
    end
  end

  defp merge_values(base_value, override_value, key_path, settings)
       when is_list(base_value) and is_list(override_value) do
    case list_strategy_for(key_path, settings) do
      :append -> base_value ++ override_value
      :replace -> override_value
    end
  end

  defp merge_values(_base_value, override_value, _key_path, _settings), do: override_value

  @spec list_strategy_for(key_path(), map()) :: list_strategy()
  defp list_strategy_for(key_path, %{list_strategies: strategies, list_strategy: fallback}) do
    Map.get(strategies, key_path, fallback)
  end

  @spec locked?(key_path(), map()) :: boolean()
  defp locked?(key_path, %{locked: locked}), do: MapSet.member?(locked, key_path)

  @spec struct?(map()) :: boolean()
  defp struct?(%_{}), do: true
  defp struct?(_map), do: false
end