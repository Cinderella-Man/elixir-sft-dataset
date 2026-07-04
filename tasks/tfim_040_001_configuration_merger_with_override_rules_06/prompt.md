# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

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

  @type key_path    :: [atom()]
  @type strategy    :: :replace | :append
  @type config_map  :: map()

  @type opts :: [
    list_strategy:   strategy(),
    list_strategies: %{key_path() => strategy()},
    locked:          [key_path()]
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
    global_strategy  = Keyword.get(opts, :list_strategy, :replace)
    per_key_raw      = Keyword.get(opts, :list_strategies, %{})
    locked_raw       = Keyword.get(opts, :locked, [])

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
      per_key_strategies:   per_key,
      locked_paths:         locked
    }
  end

  # Accept both list paths ([:a, :b]) and tuple paths ({:a, :b}) transparently.
  defp normalise_path(path, _opt) when is_list(path),  do: path
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
      :append  -> base_val ++ override_val
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

## Test harness — implement the `# TODO` test

```elixir
defmodule ConfigMergerTest do
  use ExUnit.Case, async: true

  # -------------------------------------------------------
  # Basic scalar merging
  # -------------------------------------------------------

  test "override replaces scalar at top-level key" do
    base = %{host: "localhost", port: 4000}
    override = %{port: 9000}

    result = ConfigMerger.merge(base, override)

    assert result.host == "localhost"
    assert result.port == 9000
  end

  test "keys absent in override are preserved from base" do
    base = %{a: 1, b: 2, c: 3}
    override = %{b: 99}

    result = ConfigMerger.merge(base, override)

    assert result.a == 1
    assert result.b == 99
    assert result.c == 3
  end

  test "keys present only in override are added" do
    base = %{a: 1}
    override = %{b: 2}

    result = ConfigMerger.merge(base, override)

    assert result.a == 1
    assert result.b == 2
  end

  # -------------------------------------------------------
  # Deep merging (nested maps)
  # -------------------------------------------------------

  test "nested map is deep-merged, not replaced wholesale" do
    base = %{db: %{host: "localhost", port: 5432, name: "prod"}}
    override = %{db: %{port: 5433}}

    result = ConfigMerger.merge(base, override)

    assert result.db.host == "localhost"
    assert result.db.port == 5433
    assert result.db.name == "prod"
  end

  test "3-level deep merge preserves untouched branches" do
    # TODO
  end

  test "4-level deep merge" do
    base = %{a: %{b: %{c: %{d: 1, e: 2}}}}
    override = %{a: %{b: %{c: %{d: 99}}}}

    result = ConfigMerger.merge(base, override)

    assert result.a.b.c.d == 99
    assert result.a.b.c.e == 2
  end

  # -------------------------------------------------------
  # List strategy — replace (default)
  # -------------------------------------------------------

  test "lists are replaced by default" do
    base = %{tags: ["a", "b", "c"]}
    override = %{tags: ["x"]}

    result = ConfigMerger.merge(base, override)

    assert result.tags == ["x"]
  end

  test "explicit :replace strategy replaces lists" do
    base = %{tags: [1, 2, 3]}
    override = %{tags: [4, 5]}

    result = ConfigMerger.merge(base, override, list_strategy: :replace)

    assert result.tags == [4, 5]
  end

  # -------------------------------------------------------
  # List strategy — append
  # -------------------------------------------------------

  test ":append strategy concatenates lists" do
    base = %{plugins: ["plug_a", "plug_b"]}
    override = %{plugins: ["plug_c"]}

    result = ConfigMerger.merge(base, override, list_strategy: :append)

    assert result.plugins == ["plug_a", "plug_b", "plug_c"]
  end

  test ":append on nested list" do
    base = %{server: %{allowed_ips: ["10.0.0.1"]}}
    override = %{server: %{allowed_ips: ["10.0.0.2", "10.0.0.3"]}}

    result = ConfigMerger.merge(base, override, list_strategy: :append)

    assert result.server.allowed_ips == ["10.0.0.1", "10.0.0.2", "10.0.0.3"]
  end

  # -------------------------------------------------------
  # Per-key list strategy
  # -------------------------------------------------------

  test "per-key list strategy overrides global strategy" do
    base = %{
      tags: ["a", "b"],
      plugins: ["core"]
    }

    override = %{
      tags: ["c"],
      plugins: ["extra"]
    }

    result =
      ConfigMerger.merge(base, override,
        list_strategy: :replace,
        list_strategies: %{[:tags] => :append}
      )

    # :tags uses per-key :append
    assert result.tags == ["a", "b", "c"]
    # :plugins uses global :replace
    assert result.plugins == ["extra"]
  end

  test "per-key strategy on deeply nested list" do
    base = %{app: %{server: %{hosts: ["h1"]}}}
    override = %{app: %{server: %{hosts: ["h2"]}}}

    result =
      ConfigMerger.merge(base, override, list_strategies: %{[:app, :server, :hosts] => :append})

    assert result.app.server.hosts == ["h1", "h2"]
  end

  # -------------------------------------------------------
  # Locked keys
  # -------------------------------------------------------

  test "locked top-level key is not overridden" do
    base = %{secret: "base_secret", other: "base"}
    override = %{secret: "hacked!", other: "overridden"}

    result = ConfigMerger.merge(base, override, locked: [[:secret]])

    assert result.secret == "base_secret"
    assert result.other == "overridden"
  end

  test "locked nested key is not overridden" do
    base = %{db: %{password: "s3cr3t", host: "localhost"}}
    override = %{db: %{password: "pwned", host: "evil.host"}}

    result = ConfigMerger.merge(base, override, locked: [[:db, :password]])

    assert result.db.password == "s3cr3t"
    assert result.db.host == "evil.host"
  end

  test "locked key at one path does not protect same key at another path" do
    base = %{
      primary: %{token: "real_token"},
      secondary: %{token: "also_real"}
    }

    override = %{
      primary: %{token: "fake_token"},
      secondary: %{token: "replaced"}
    }

    result =
      ConfigMerger.merge(base, override, locked: [[:primary, :token]])

    assert result.primary.token == "real_token"
    assert result.secondary.token == "replaced"
  end

  test "multiple locked keys work together" do
    base = %{a: 1, b: 2, c: 3}
    override = %{a: 10, b: 20, c: 30}

    result = ConfigMerger.merge(base, override, locked: [[:a], [:c]])

    assert result.a == 1
    assert result.b == 20
    assert result.c == 3
  end

  # -------------------------------------------------------
  # Combined scenarios
  # -------------------------------------------------------

  test "locked key inside deep map with other keys merging normally" do
    base = %{
      app: %{
        auth: %{secret_key: "do-not-touch", algo: "HS256"},
        name: "MyApp"
      }
    }

    override = %{
      app: %{
        auth: %{secret_key: "compromised", algo: "RS256"},
        name: "EvilApp"
      }
    }

    result =
      ConfigMerger.merge(base, override, locked: [[:app, :auth, :secret_key]])

    assert result.app.auth.secret_key == "do-not-touch"
    assert result.app.auth.algo == "RS256"
    assert result.app.name == "EvilApp"
  end

  test "append list strategy + locked key in same merge" do
    base = %{
      allowed: ["user_a"],
      pin: "1234"
    }

    override = %{
      allowed: ["user_b"],
      pin: "9999"
    }

    result =
      ConfigMerger.merge(base, override,
        list_strategy: :append,
        locked: [[:pin]]
      )

    assert result.allowed == ["user_a", "user_b"]
    assert result.pin == "1234"
  end

  test "merging empty override returns base unchanged" do
    base = %{a: 1, b: %{c: 2}}

    result = ConfigMerger.merge(base, %{})

    assert result == base
  end

  test "merging empty base with override returns override" do
    override = %{x: 10, y: %{z: 20}}

    result = ConfigMerger.merge(%{}, override)

    assert result == override
  end
end
```
