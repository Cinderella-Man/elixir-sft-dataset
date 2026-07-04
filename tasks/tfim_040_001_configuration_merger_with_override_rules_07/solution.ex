  test "4-level deep merge" do
    base = %{a: %{b: %{c: %{d: 1, e: 2}}}}
    override = %{a: %{b: %{c: %{d: 99}}}}

    result = ConfigMerger.merge(base, override)

    assert result.a.b.c.d == 99
    assert result.a.b.c.e == 2
  end