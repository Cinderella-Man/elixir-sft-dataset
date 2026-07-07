  test "from_major/2 preserves currency and raises on bad input" do
    assert Money.from_major(1, :EUR).currency == :EUR
    assert_raise ArgumentError, fn -> Money.from_major("12", :USD) end
    assert_raise ArgumentError, fn -> Money.from_major(12, :XYZ) end
  end