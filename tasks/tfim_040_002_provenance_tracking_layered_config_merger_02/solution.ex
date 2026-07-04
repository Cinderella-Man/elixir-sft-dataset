  test "single layer returns config unchanged with self provenance" do
    result = LayeredConfig.merge([{:base, %{a: 1, b: %{c: 2}}}])

    assert result.config == %{a: 1, b: %{c: 2}}
    assert result.provenance[[:a]] == :base
    assert result.provenance[[:b, :c]] == :base
  end