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

  test "provenance drops paths whose subtree a higher layer replaced with a scalar" do
    layers = [
      {:base, %{db: %{host: "localhost", port: 5432}}},
      {:env, %{db: "disabled"}}
    ]

    result = LayeredConfig.merge(layers)

    assert result.config == %{db: "disabled"}
    assert result.provenance[[:db]] == :env
    refute Map.has_key?(result.provenance, [:db, :host])
    refute Map.has_key?(result.provenance, [:db, :port])
  end

  test "locked path absent from earlier layers may still be set by a higher layer" do
    layers = [
      {:base, %{db: %{host: "localhost"}}},
      {:env, %{db: %{password: "fresh"}, token: "new"}}
    ]

    result = LayeredConfig.merge(layers, locked: [[:db, :password], [:token]])

    assert result.config.db.password == "fresh"
    assert result.config.token == "new"
    assert result.provenance[[:db, :password]] == :env
    assert result.provenance[[:token]] == :env
  end

  test "per-key replace overrides a global append strategy" do
    layers = [
      {:base, %{tags: ["a"], plugins: ["core"]}},
      {:env, %{tags: ["b"], plugins: ["extra"]}}
    ]

    result =
      LayeredConfig.merge(layers,
        list_strategy: :append,
        list_strategies: %{[:tags] => :replace}
      )

    assert result.config.tags == ["b"]
    assert result.config.plugins == ["core", "extra"]
    assert result.provenance[[:tags]] == :env
    assert result.provenance[[:plugins]] == [:base, :env]
  end

  test "tuple key paths work for locked and list_strategies options" do
    layers = [
      {:base, %{db: %{password: "keep", tags: ["a"]}}},
      {:env, %{db: %{password: "hack", tags: ["b"]}}}
    ]

    result =
      LayeredConfig.merge(layers,
        locked: [{:db, :password}],
        list_strategies: %{{:db, :tags} => :append}
      )

    assert result.config.db.password == "keep"
    assert result.config.db.tags == ["a", "b"]
    assert result.provenance[[:db, :password]] == :base
    assert result.provenance[[:db, :tags]] == [:base, :env]
  end

  test "append provenance omits a middle layer that contributed no elements" do
    layers = [
      {:base, %{plugins: ["core"]}},
      {:file, %{other: 1}},
      {:env, %{plugins: ["metrics"]}}
    ]

    result = LayeredConfig.merge(layers, list_strategy: :append)

    assert result.config.plugins == ["core", "metrics"]
    assert result.provenance[[:plugins]] == [:base, :env]
    assert result.provenance[[:other]] == :file
  end

  test "merge result exposes exactly the config and provenance keys" do
    result = LayeredConfig.merge([{:base, %{a: 1}}, {:env, %{a: 2}}])

    assert result |> Map.keys() |> Enum.sort() == [:config, :provenance]
    assert map_size(result) == 2
  end

  # -------------------------------------------------------
  # Append with a single contributing layer
  # -------------------------------------------------------

  # Under :append the contributors of a list leaf are exactly the layers that set a
  # list at that path, in precedence order; a layer that sets no list there is never
  # named, including when only one layer contributes at all. The provenance is read
  # through List.wrap/1 so a lone contributor is accepted either as its bare name or
  # as a one-element list of names -- what is pinned is *which* layers are named.
  test "append names only the single contributing layer, never the silent ones" do
    lower_only = [
      {:base, %{plugins: ["core"]}},
      {:file, %{other: 1}},
      {:env, %{unrelated: true}}
    ]

    result = LayeredConfig.merge(lower_only, list_strategy: :append)

    assert result.config.plugins == ["core"]
    assert List.wrap(result.provenance[[:plugins]]) == [:base]

    higher_only = [
      {:base, %{db: %{host: "localhost"}}},
      {:file, %{db: %{port: 5432}}},
      {:env, %{db: %{tags: ["metrics"]}}}
    ]

    nested = LayeredConfig.merge(higher_only, list_strategy: :append)

    assert nested.config.db.tags == ["metrics"]
    assert List.wrap(nested.provenance[[:db, :tags]]) == [:env]
  end
end
