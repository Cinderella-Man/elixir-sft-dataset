  test "keys present only in override are added" do
    base = %{a: 1}
    override = %{b: 2}

    result = ConfigMerger.merge(base, override)

    assert result.a == 1
    assert result.b == 2
  end