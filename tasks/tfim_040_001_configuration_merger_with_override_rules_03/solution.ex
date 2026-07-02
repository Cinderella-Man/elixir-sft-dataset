  test "keys absent in override are preserved from base" do
    base = %{a: 1, b: 2, c: 3}
    override = %{b: 99}

    result = ConfigMerger.merge(base, override)

    assert result.a == 1
    assert result.b == 99
    assert result.c == 3
  end