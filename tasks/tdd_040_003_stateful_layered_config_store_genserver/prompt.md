# Make this test suite pass

Below is a complete, self-contained ExUnit test suite. Treat it as the
full specification: write the module (or modules) under test so that
every test passes. Use only what the tests themselves require — the
standard library and OTP unless the suite references anything else.
Follow idiomatic Elixir house style (`@moduledoc`, `@doc` + `@spec` on
the public API, no compiler warnings).

## The test suite

```elixir
defmodule ConfigStoreTest do
  use ExUnit.Case, async: false

  defp start(opts) do
    {:ok, pid} = ConfigStore.start_link(opts)
    pid
  end

  test "base-only config is returned when no layers added" do
    s = start(base: %{a: 1, b: %{c: 2}})

    assert ConfigStore.get_config(s) == %{a: 1, b: %{c: 2}}
    assert ConfigStore.layers(s) == []
  end

  test "put_layer overrides scalars from the base" do
    s = start(base: %{host: "localhost", port: 4000})

    assert :ok == ConfigStore.put_layer(s, :env, %{port: 9000})

    assert ConfigStore.get_config(s) == %{host: "localhost", port: 9000}
    assert ConfigStore.layers(s) == [:env]
  end

  test "nested maps are deep-merged across base and layers" do
    s = start(base: %{db: %{host: "localhost", port: 5432, name: "prod"}})
    ConfigStore.put_layer(s, :override, %{db: %{port: 5433}})

    assert ConfigStore.get_config(s).db == %{host: "localhost", port: 5433, name: "prod"}
  end

  test "later layer wins over earlier layer" do
    s = start(base: %{level: :info})
    ConfigStore.put_layer(s, :file, %{level: :warn})
    ConfigStore.put_layer(s, :env, %{level: :error})

    assert ConfigStore.get_config(s).level == :error
    assert ConfigStore.layers(s) == [:file, :env]
  end

  test "replacing a layer keeps its precedence position" do
    s = start(base: %{v: 0})
    ConfigStore.put_layer(s, :low, %{v: 1})
    ConfigStore.put_layer(s, :high, %{v: 2})

    # Re-put :low with a new value; it must still be lower precedence than :high.
    ConfigStore.put_layer(s, :low, %{v: 99})

    assert ConfigStore.layers(s) == [:low, :high]
    assert ConfigStore.get_config(s).v == 2
  end

  test "drop_layer removes a layer" do
    s = start(base: %{v: 0})
    ConfigStore.put_layer(s, :a, %{v: 1})
    ConfigStore.put_layer(s, :b, %{v: 2})

    assert :ok == ConfigStore.drop_layer(s, :b)

    assert ConfigStore.layers(s) == [:a]
    assert ConfigStore.get_config(s).v == 1
  end

  test "get/2 fetches by key-path and returns nil when absent" do
    s = start(base: %{app: %{server: %{port: 80}}})
    ConfigStore.put_layer(s, :env, %{app: %{server: %{port: 443}}})

    assert ConfigStore.get(s, [:app, :server, :port]) == 443
    assert ConfigStore.get(s, [:app, :missing]) == nil
  end

  test "append list strategy concatenates base and layer lists" do
    s = start(base: %{plugins: ["core"]}, list_strategy: :append)
    ConfigStore.put_layer(s, :a, %{plugins: ["auth"]})
    ConfigStore.put_layer(s, :b, %{plugins: ["metrics"]})

    assert ConfigStore.get_config(s).plugins == ["core", "auth", "metrics"]
  end

  test "per-key list strategy overrides the global strategy" do
    s =
      start(
        base: %{tags: ["a"], plugins: ["core"]},
        list_strategy: :replace,
        list_strategies: %{[:tags] => :append}
      )

    ConfigStore.put_layer(s, :env, %{tags: ["b"], plugins: ["extra"]})

    cfg = ConfigStore.get_config(s)
    assert cfg.tags == ["a", "b"]
    assert cfg.plugins == ["extra"]
  end

  test "locked key-path cannot be changed by any layer" do
    s = start(base: %{db: %{password: "s3cr3t", host: "localhost"}}, locked: [[:db, :password]])
    ConfigStore.put_layer(s, :env, %{db: %{password: "pwned", host: "evil.host"}})

    cfg = ConfigStore.get_config(s)
    assert cfg.db.password == "s3cr3t"
    assert cfg.db.host == "evil.host"
  end

  test "named server can be addressed by its registered name" do
    {:ok, _pid} = ConfigStore.start_link(name: :cfg_named_test, base: %{a: 1})
    ConfigStore.put_layer(:cfg_named_test, :env, %{a: 2})

    assert ConfigStore.get(:cfg_named_test, [:a]) == 2
  end

  test "locked key-path absent from the base cannot be introduced by a layer" do
    s = start(base: %{db: %{host: "localhost"}}, locked: [[:db, :password]])
    ConfigStore.put_layer(s, :env, %{db: %{password: "pwned"}})

    assert ConfigStore.get(s, [:db, :password]) == nil
    assert ConfigStore.get(s, [:db, :host]) == "localhost"
  end

  test "locked key-paths supplied as tuples are honoured" do
    s = start(base: %{db: %{password: "s3cr3t", host: "localhost"}}, locked: [{:db, :password}])
    ConfigStore.put_layer(s, :env, %{db: %{password: "pwned", host: "evil.host"}})

    assert ConfigStore.get(s, [:db, :password]) == "s3cr3t"
    assert ConfigStore.get(s, [:db, :host]) == "evil.host"
  end

  test "list_strategies path given as a tuple applies to a nested key-path" do
    s =
      start(
        base: %{app: %{plugins: ["core"]}},
        list_strategies: %{{:app, :plugins} => :append}
      )

    ConfigStore.put_layer(s, :env, %{app: %{plugins: ["auth"]}})

    assert ConfigStore.get(s, [:app, :plugins]) == ["core", "auth"]
  end

  test "re-putting a layer replaces its whole map rather than merging with the old map" do
    s = start(base: %{})
    ConfigStore.put_layer(s, :env, %{a: 1, stale: true})
    ConfigStore.put_layer(s, :env, %{a: 2})

    assert ConfigStore.get_config(s) == %{a: 2}
    assert ConfigStore.layers(s) == [:env]
  end

  test "base defaults to an empty map when the option is omitted" do
    s = start([])

    assert ConfigStore.get_config(s) == %{}

    ConfigStore.put_layer(s, :env, %{a: 1})

    assert ConfigStore.get_config(s) == %{a: 1}
  end

  test "list_strategy defaults to replace when the option is omitted" do
    s = start(base: %{plugins: ["core"]})
    ConfigStore.put_layer(s, :env, %{plugins: ["auth"]})

    assert ConfigStore.get(s, [:plugins]) == ["auth"]
  end

  test "locked top-level path absent from the base stays out of the effective config" do
    s = start(base: %{host: "localhost"}, locked: [[:token]])
    ConfigStore.put_layer(s, :env, %{token: "pwned", host: "evil.host"})

    # The locked key is absent, not merely nil-valued, while its sibling still changes.
    assert ConfigStore.get_config(s) == %{host: "evil.host"}
    assert ConfigStore.get(s, [:token]) == nil
  end

  test "successive layers cannot introduce a deep locked path the base leaves undefined" do
    s = start(base: %{db: %{opts: %{ssl: true}}}, locked: [[:db, :opts, :password]])
    ConfigStore.put_layer(s, :file, %{db: %{opts: %{password: "one", ssl: false}}})
    ConfigStore.put_layer(s, :env, %{db: %{opts: %{password: "two"}}})

    assert ConfigStore.get_config(s) == %{db: %{opts: %{ssl: false}}}
    assert ConfigStore.get(s, [:db, :opts, :password]) == nil
  end

  test "a single layer cannot introduce a locked path when the base lacks its parent" do
    # The wholesale-copy path: the base defines NOTHING, so the layer's whole
    # subtree is introduced at once — the locked descendant must be stripped
    # at every depth, not smuggled in with the copy.
    s = start(base: %{}, locked: [[:db, :password]])
    ConfigStore.put_layer(s, :env, %{db: %{password: "pwned", host: "h"}})

    assert ConfigStore.get(s, [:db, :password]) == nil
    assert ConfigStore.get(s, [:db, :host]) == "h"
  end
end
```

Give me the complete implementation in a single file — the module(s)
alone, not the tests.
