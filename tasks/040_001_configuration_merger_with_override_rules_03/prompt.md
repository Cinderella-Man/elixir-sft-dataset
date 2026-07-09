Implement the private `merge_values/4` function. It receives `base_val`,
`override_val`, the `key_path` (a list of atoms from the root to the current
key), and the resolved `opts` map, and returns the value that should be stored at
that key path.

It must handle three cases:

1. **Both values are maps** — recurse into them with `do_merge/4`, passing the
   current `key_path` and `opts`, so nested maps are deep-merged rather than
   replaced.
2. **Both values are lists** — look up the applicable strategy for this
   `key_path` with `list_strategy_for/2`. If the strategy is `:replace`, return
   `override_val`; if it is `:append`, return `base_val ++ override_val`.
3. **Any other combination** — scalar vs scalar, or a type mismatch between the
   two values — the override wins, so return `override_val`.

```elixir
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
    # Collect all keys from both maps.
    all_keys = Map.keys(base) ++ Map.keys(override)
    all_keys = Enum.uniq(all_keys)

    Map.new(all_keys, fn key ->
      key_path = current_path ++ [key]

      merged_value =
        cond do
          # Key only exists in base — keep it unconditionally.
          not Map.has_key?(override, key) ->
            Map.fetch!(base, key)

          # Key only exists in override — but respect lock (do not introduce
          # a locked key if it genuinely isn't in base either; if it *is* in
          # base the guard below handles it).
          not Map.has_key?(base, key) ->
            Map.fetch!(override, key)

          # Both maps have the key. Check lock first.
          locked?(key_path, opts) ->
            Map.fetch!(base, key)

          # Both maps have the key, key is not locked — merge the values.
          true ->
            merge_values(
              Map.fetch!(base, key),
              Map.fetch!(override, key),
              key_path,
              opts
            )
        end

      {key, merged_value}
    end)
  end

  # ---------------------------------------------------------------------------
  # Value-level merging
  # ---------------------------------------------------------------------------

  defp merge_values(base_val, override_val, key_path, opts) do
    # TODO
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # Check whether a key path is in the locked set.
  defp locked?(key_path, %{locked_paths: locked_paths}) do
    key_path in locked_paths
  end

  # Look up the list strategy for a given key path.
  # Per-key strategies take precedence over the global default.
  defp list_strategy_for(key_path, %{per_key_strategies: per_key, global_list_strategy: global}) do
    Map.get(per_key, key_path, global)
  end
end
```