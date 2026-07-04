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