defmodule ConfigMerger do
  @moduledoc """
  Deep-merges configuration maps with a configurable override strategy.

  ## Options

    * `:list_strategy` - Global list merge strategy. Either `:replace` (default) or
      `:append`. `:replace` means the override list wins outright; `:append` means
      the override list is concatenated onto the end of the base list.

    * `:list_strategies` - A map of `key_path => strategy` pairs that override the
      global `:list_strategy` for specific paths. Key paths are lists of atoms, e.g.
      `[:servers, :hosts]`. Values are `:replace` or `:append`.

    * `:locked` - A list of key paths (each a list of atoms) whose values must not
      be changed by the override. The base value is always preserved for locked paths.
      A locked path the base does not define cannot be injected by the override —
      the key is simply absent from the result.

  ## Examples

      iex> base   = %{db: %{host: "localhost", port: 5432}, tags: ["a"]}
      iex> over   = %{db: %{port: 5433, name: "mydb"},      tags: ["b"]}

      # Default (scalars replaced, lists replaced)
      iex> ConfigMerger.merge(base, over)
      %{db: %{host: "localhost", port: 5433, name: "mydb"}, tags: ["b"]}

      # Append lists globally
      iex> ConfigMerger.merge(base, over, list_strategy: :append)
      %{db: %{host: "localhost", port: 5433, name: "mydb"}, tags: ["a", "b"]}

      # Lock a nested key
      iex> ConfigMerger.merge(base, over, locked: [[:db, :port]])
      %{db: %{host: "localhost", port: 5432, name: "mydb"}, tags: ["b"]}
  """

  @type key_path :: [atom()]
  @type strategy :: :replace | :append
  @type config_map :: map()

  @type opts :: [
          list_strategy: strategy(),
          list_strategies: %{key_path() => strategy()},
          locked: [key_path()]
        ]

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Deep-merges `override_config` into `base_config`.

  Returns the merged map directly.
  """
  @spec merge(config_map(), config_map(), opts()) :: config_map()
  def merge(base_config, override_config, opts \\ [])
      when is_map(base_config) and is_map(override_config) do
    resolved_opts = resolve_opts(opts)
    do_merge(base_config, override_config, _current_path = [], resolved_opts)
  end

  # ---------------------------------------------------------------------------
  # Option normalisation
  # ---------------------------------------------------------------------------

  defp resolve_opts(opts) do
    global_strategy = Keyword.get(opts, :list_strategy, :replace)
    per_key_raw = Keyword.get(opts, :list_strategies, %{})
    locked_raw = Keyword.get(opts, :locked, [])

    unless global_strategy in [:replace, :append] do
      raise ArgumentError,
            "`:list_strategy` must be `:replace` or `:append`, got: #{inspect(global_strategy)}"
    end

    # Normalise per-key strategies: allow both list and tuple keys for ergonomics,
    # but store everything as lists internally.
    per_key =
      Map.new(per_key_raw, fn {path, strat} ->
        normalised_path = normalise_path(path, :list_strategies)

        unless strat in [:replace, :append] do
          raise ArgumentError,
                "`:list_strategies` values must be `:replace` or `:append`, " <>
                  "got #{inspect(strat)} for path #{inspect(normalised_path)}"
        end

        {normalised_path, strat}
      end)

    locked = Enum.map(locked_raw, &normalise_path(&1, :locked))

    %{
      global_list_strategy: global_strategy,
      per_key_strategies: per_key,
      locked_paths: locked
    }
  end

  # Accept both list paths ([:a, :b]) and tuple paths ({:a, :b}) transparently.
  defp normalise_path(path, _opt) when is_list(path), do: path
  defp normalise_path(path, _opt) when is_tuple(path), do: Tuple.to_list(path)

  defp normalise_path(path, opt) do
    raise ArgumentError,
          "Key paths in `#{inspect(opt)}` must be lists or tuples of atoms, " <>
            "got: #{inspect(path)}"
  end

  # ---------------------------------------------------------------------------
  # Recursive merge
  # ---------------------------------------------------------------------------

  defp do_merge(base, override, current_path, opts) when is_map(base) and is_map(override) do
    # Collect all keys from both maps, base keys first for stable traversal.
    all_keys = Enum.uniq(Map.keys(base) ++ Map.keys(override))

    Enum.reduce(all_keys, %{}, fn key, acc ->
      key_path = current_path ++ [key]

      cond do
        # Key only exists in base — keep it unconditionally.
        not Map.has_key?(override, key) ->
          Map.put(acc, key, Map.fetch!(base, key))

        # The path is locked: the base value (if any) is authoritative. When the
        # base does not define the key, the override cannot inject it — a locked
        # path is never writable from the override side.
        locked?(key_path, opts) ->
          case Map.fetch(base, key) do
            {:ok, base_value} -> Map.put(acc, key, base_value)
            :error -> acc
          end

        # Key only exists in the override and is not itself locked. A MAP
        # value cannot be copied wholesale: locked paths nested beneath it
        # must still be stripped — merge it into an empty base so every
        # depth gets its locked? check.
        not Map.has_key?(base, key) ->
          value = Map.fetch!(override, key)

          if is_map(value) do
            Map.put(acc, key, do_merge(%{}, value, key_path, opts))
          else
            Map.put(acc, key, value)
          end

        # Both maps have the key and it is not locked — merge the values.
        true ->
          merged = merge_values(Map.fetch!(base, key), Map.fetch!(override, key), key_path, opts)
          Map.put(acc, key, merged)
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # Value-level merging
  # ---------------------------------------------------------------------------

  # Both values are maps → recurse.
  defp merge_values(base_val, override_val, key_path, opts)
       when is_map(base_val) and is_map(override_val) do
    do_merge(base_val, override_val, key_path, opts)
  end

  # Both values are lists → apply the applicable list strategy.
  defp merge_values(base_val, override_val, key_path, opts)
       when is_list(base_val) and is_list(override_val) do
    case list_strategy_for(key_path, opts) do
      :replace -> override_val
      :append -> base_val ++ override_val
    end
  end

  # Any other combination (scalar vs scalar, type mismatch, etc.) → override wins.
  defp merge_values(_base_val, override_val, _key_path, _opts), do: override_val

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # Check whether a key path is in the locked set.
  defp locked?(key_path, %{locked_paths: locked_paths}) do
    key_path in locked_paths
  end

  # Look up the list strategy for a given key path.
  # Per-key strategies take precedence over the global default.
  defp list_strategy_for(
         key_path,
         %{per_key_strategies: per_key, global_list_strategy: global}
       ) do
    Map.get(per_key, key_path, global)
  end
end
