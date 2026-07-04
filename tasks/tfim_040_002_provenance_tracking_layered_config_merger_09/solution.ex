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