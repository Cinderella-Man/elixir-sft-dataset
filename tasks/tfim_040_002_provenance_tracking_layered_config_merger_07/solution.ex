  test "lists are replaced by default" do
    layers = [{:base, %{tags: ["a", "b"]}}, {:env, %{tags: ["x"]}}]

    result = LayeredConfig.merge(layers)

    assert result.config.tags == ["x"]
    assert result.provenance[[:tags]] == :env
  end