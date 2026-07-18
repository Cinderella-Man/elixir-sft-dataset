  test "merging empty override returns base unchanged" do
    base = %{a: 1, b: %{c: 2}}

    result = ConfigMerger.merge(base, %{})

    assert result == base
  end