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