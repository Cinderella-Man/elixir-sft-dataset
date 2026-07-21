# Make this test suite pass

Below is a complete, self-contained ExUnit test suite. Treat it as the
full specification: write the module (or modules) under test so that
every test passes. Use only what the tests themselves require — the
standard library and OTP unless the suite references anything else.
Follow idiomatic Elixir house style (`@moduledoc`, `@doc` + `@spec` on
the public API, no compiler warnings).

## The test suite

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
    base = %{
      app: %{
        server: %{host: "0.0.0.0", port: 80, ssl: false},
        cache: %{ttl: 300}
      }
    }

    override = %{
      app: %{
        server: %{port: 443, ssl: true}
      }
    }

    result = ConfigMerger.merge(base, override)

    assert result.app.server.host == "0.0.0.0"
    assert result.app.server.port == 443
    assert result.app.server.ssl == true
    assert result.app.cache.ttl == 300
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

  test "locked path is not injectable by override when base lacks the key" do
    base = %{db: %{host: "localhost"}}
    override = %{db: %{host: "evil.host", password: "pwned"}}

    result = ConfigMerger.merge(base, override, locked: [[:db, :password]])

    assert result.db.host == "evil.host"
    refute Map.has_key?(result.db, :password)
  end

  test "per-key :replace takes precedence over global :append strategy" do
    base = %{tags: ["a", "b"], plugins: ["core"]}
    override = %{tags: ["c"], plugins: ["extra"]}

    result =
      ConfigMerger.merge(base, override,
        list_strategy: :append,
        list_strategies: %{[:tags] => :replace}
      )

    assert result.tags == ["c"]
    assert result.plugins == ["core", "extra"]
  end

  test "locked path pointing at a map preserves the entire base subtree" do
    base = %{db: %{host: "localhost", port: 5432}, app: %{name: "MyApp"}}
    override = %{db: %{host: "evil.host", port: 6666, extra: true}, app: %{name: "EvilApp"}}

    result = ConfigMerger.merge(base, override, locked: [[:db]])

    assert result.db == %{host: "localhost", port: 5432}
    assert result.app.name == "EvilApp"
  end

  test "locked top-level key does not protect the same key nested deeper" do
    base = %{token: "root_token", db: %{token: "nested_token"}}
    override = %{token: "new_root", db: %{token: "new_nested"}}

    result = ConfigMerger.merge(base, override, locked: [[:token]])

    assert result.token == "root_token"
    assert result.db.token == "new_nested"
  end

  test "atom and boolean scalars are replaced including false values" do
    base = %{mode: :production, debug: true, verbose: false}
    override = %{mode: :staging, debug: false, verbose: true}

    result = ConfigMerger.merge(base, override)

    assert result.mode == :staging
    assert result.debug == false
    assert result.verbose == true
  end

  test ":append with empty lists on either side yields the other list" do
    result_empty_override =
      ConfigMerger.merge(%{tags: ["a"]}, %{tags: []}, list_strategy: :append)

    result_empty_base = ConfigMerger.merge(%{tags: []}, %{tags: ["b"]}, list_strategy: :append)

    assert result_empty_override.tags == ["a"]
    assert result_empty_base.tags == ["b"]
  end

  test "locked top-level key absent from base is not injected by override" do
    base = %{other: "base"}
    override = %{secret: "injected", other: "overridden"}

    result = ConfigMerger.merge(base, override, locked: [[:secret]])

    refute Map.has_key?(result, :secret)
    assert result.other == "overridden"
  end

  test "locked key absent from base is not injected even when override value is a map" do
    base = %{db: %{host: "localhost"}}
    override = %{db: %{host: "evil.host", credentials: %{user: "root", password: "pwned"}}}

    result = ConfigMerger.merge(base, override, locked: [[:db, :credentials]])

    refute Map.has_key?(result.db, :credentials)
    assert result.db.host == "evil.host"
  end
end
```

Give me the complete implementation in a single file — the module(s)
alone, not the tests.
