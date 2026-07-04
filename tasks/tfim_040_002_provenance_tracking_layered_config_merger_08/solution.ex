  test "append strategy concatenates and provenance is a list of layer names" do
    layers = [{:base, %{tags: ["a"]}}, {:env, %{tags: ["b"]}}]

    result = LayeredConfig.merge(layers, list_strategy: :append)

    assert result.config.tags == ["a", "b"]
    assert result.provenance[[:tags]] == [:base, :env]
  end