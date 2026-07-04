  test "keys introduced by a higher layer get that layer's provenance" do
    layers = [{:base, %{a: 1}}, {:extra, %{b: %{c: 3}}}]

    result = LayeredConfig.merge(layers)

    assert result.config == %{a: 1, b: %{c: 3}}
    assert result.provenance[[:a]] == :base
    assert result.provenance[[:b, :c]] == :extra
  end