defmodule LayeredConfigTest do
  use ExUnit.Case, async: false

  # -------------------------------------------------------
  # Basic scalar layering + provenance
  # -------------------------------------------------------

  test "single layer returns config unchanged with self provenance" do
    result = LayeredConfig.merge([{:base, %{a: 1, b: %{c: 2}}}])

    assert result.config == %{a: 1, b: %{c: 2}}
    assert result.provenance[[:a]] == :base
    assert result.provenance[[:b, :c]] == :base
  end

  test "later layer overrides scalar and records provenance" do
    layers = [{:base, %{host: "localhost", port: 4000}}, {:env, %{port: 9000}}]

    result = LayeredConfig.merge(layers)

    assert result.config == %{host: "localhost", port: 9000}
    assert result.provenance[[:host]] == :base
    assert result.provenance[[:port]] == :env
  end

  test "three layers apply in increasing precedence" do
    layers = [
      {:default, %{level: :info, retries: 1}},
      {:file, %{level: :warn}},
      {:env, %{retries: 5}}
    ]

    result = LayeredConfig.merge(layers)

    assert result.config == %{level: :warn, retries: 5}
    assert result.provenance[[:level]] == :file
    assert result.provenance[[:retries]] == :env
  end

  # -------------------------------------------------------
  # Deep merge
  # -------------------------------------------------------

  test "nested map is deep-merged across layers with per-leaf provenance" do
    layers = [
      {:base, %{db: %{host: "localhost", port: 5432, name: "prod"}}},
      {:override, %{db: %{port: 5433}}}
    ]

    result = LayeredConfig.merge(layers)

    assert result.config.db == %{host: "localhost", port: 5433, name: "prod"}
    assert result.provenance[[:db, :host]] == :base
    assert result.provenance[[:db, :port]] == :override
    assert result.provenance[[:db, :name]] == :base
  end

  test "keys introduced by a higher layer get that layer's provenance" do
    layers = [{:base, %{a: 1}}, {:extra, %{b: %{c: 3}}}]

    result = LayeredConfig.merge(layers)

    assert result.config == %{a: 1, b: %{c: 3}}
    assert result.provenance[[:a]] == :base
    assert result.provenance[[:b, :c]] == :extra
  end

  # -------------------------------------------------------
  # List strategies
  # -------------------------------------------------------

  test "lists are replaced by default" do
    layers = [{:base, %{tags: ["a", "b"]}}, {:env, %{tags: ["x"]}}]

    result = LayeredConfig.merge(layers)

    assert result.config.tags == ["x"]
    assert result.provenance[[:tags]] == :env
  end

  test "append strategy concatenates and provenance is a list of layer names" do
    layers = [{:base, %{tags: ["a"]}}, {:env, %{tags: ["b"]}}]

    result = LayeredConfig.merge(layers, list_strategy: :append)

    assert result.config.tags == ["a", "b"]
    assert result.provenance[[:tags]] == [:base, :env]
  end

  test "append across three layers accumulates provenance in order" do
    layers = [
      {:base, %{plugins: ["core"]}},
      {:file, %{plugins: ["auth"]}},
      {:env, %{plugins: ["metrics"]}}
    ]

    result = LayeredConfig.merge(layers, list_strategy: :append)

    assert result.config.plugins == ["core", "auth", "metrics"]
    assert result.provenance[[:plugins]] == [:base, :file, :env]
  end

  test "per-key list strategy overrides the global strategy" do
    layers = [
      {:base, %{tags: ["a"], plugins: ["core"]}},
      {:env, %{tags: ["b"], plugins: ["extra"]}}
    ]

    result =
      LayeredConfig.merge(layers,
        list_strategy: :replace,
        list_strategies: %{[:tags] => :append}
      )

    assert result.config.tags == ["a", "b"]
    assert result.config.plugins == ["extra"]
    assert result.provenance[[:tags]] == [:base, :env]
    assert result.provenance[[:plugins]] == :env
  end

  # -------------------------------------------------------
  # Locked keys
  # -------------------------------------------------------

  test "locked key preserves the earlier value and provenance" do
    layers = [
      {:base, %{secret: "s3cr3t", other: "base"}},
      {:env, %{secret: "pwned", other: "new"}}
    ]

    result = LayeredConfig.merge(layers, locked: [[:secret]])

    assert result.config.secret == "s3cr3t"
    assert result.config.other == "new"
    assert result.provenance[[:secret]] == :base
    assert result.provenance[[:other]] == :env
  end

  test "locked nested key is preserved while siblings merge" do
    layers = [
      {:base, %{db: %{password: "keep", host: "localhost"}}},
      {:env, %{db: %{password: "hack", host: "evil.host"}}}
    ]

    result = LayeredConfig.merge(layers, locked: [[:db, :password]])

    assert result.config.db.password == "keep"
    assert result.config.db.host == "evil.host"
    assert result.provenance[[:db, :password]] == :base
    assert result.provenance[[:db, :host]] == :env
  end

  test "locking one path does not protect the same key elsewhere" do
    layers = [
      {:base, %{primary: %{token: "real"}, secondary: %{token: "also_real"}}},
      {:env, %{primary: %{token: "fake"}, secondary: %{token: "replaced"}}}
    ]

    result = LayeredConfig.merge(layers, locked: [[:primary, :token]])

    assert result.config.primary.token == "real"
    assert result.config.secondary.token == "replaced"
  end

  # -------------------------------------------------------
  # Errors
  # -------------------------------------------------------

  test "empty layer list raises ArgumentError" do
    assert_raise ArgumentError, fn -> LayeredConfig.merge([]) end
  end
end
