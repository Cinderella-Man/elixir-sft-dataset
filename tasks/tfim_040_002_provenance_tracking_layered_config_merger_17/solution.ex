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