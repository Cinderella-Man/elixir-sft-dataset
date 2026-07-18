  test "multiple locked keys work together" do
    base = %{a: 1, b: 2, c: 3}
    override = %{a: 10, b: 20, c: 30}

    result = ConfigMerger.merge(base, override, locked: [[:a], [:c]])

    assert result.a == 1
    assert result.b == 20
    assert result.c == 3
  end