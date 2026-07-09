# Task: Implement `resolve_opts/1`

Implement the private `resolve_opts/1` function for the `ConfigMerger` module.

This function normalises the user-supplied keyword `opts` into an internal
configuration map that the rest of the merge machinery consumes. It must:

- Read the following options, each with a default:
  - `:list_strategy` — the global list merge strategy, defaulting to `:replace`.
  - `:list_strategies` — a map of `key_path => strategy` pairs, defaulting to `%{}`.
  - `:locked` — a list of key paths, defaulting to `[]`.
- Validate the global `:list_strategy`: it must be either `:replace` or `:append`.
  If it is anything else, raise an `ArgumentError` whose message reports the offending
  value (via `inspect/1`).
- Normalise the per-key strategies into a new map: for each `{path, strat}` pair,
  convert `path` to its canonical list form using `normalise_path/2` (passing
  `:list_strategies` as the option name), and validate that `strat` is `:replace` or
  `:append`. If a value is invalid, raise an `ArgumentError` whose message reports the
  offending strategy and the normalised path (both via `inspect/1`). Store the result
  keyed by the normalised path.
- Normalise every entry in the `:locked` list using `normalise_path/2` (passing
  `:locked` as the option name), producing a list of canonical list paths.
- Return a map with exactly these keys:
  - `:global_list_strategy` — the validated global strategy.
  - `:per_key_strategies` — the normalised per-key strategy map.
  - `:locked_paths` — the normalised list of locked paths.

The whole module is given below, with only the body of `resolve_opts/1` replaced by
`# TODO`. Implement that body.

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
    # TODO
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

  # Both values are maps → recurse.
  defp merge_values(base_val, override_val, key_path, opts)
       when is_map(base_val) and is_map(override_val) do
    do_merge(base_val, override_val, key_path, opts)
  end

  # Both values are lists → apply the applicable list strategy.
  defp merge_values(base_val, override_val, key_path, opts)
       when is_list(base_val) and is_list(override_val) do
    strategy = list_strategy_for(key_path, opts)

    case strategy do
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
  defp list_strategy_for(key_path, %{per_key_strategies: per_key, global_list_strategy: global}) do
    Map.get(per_key, key_path, global)
  end
end
```