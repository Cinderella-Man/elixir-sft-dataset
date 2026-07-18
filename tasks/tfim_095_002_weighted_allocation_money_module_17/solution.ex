  test "allocate/2 raises on invalid ratios" do
    assert_raise ArgumentError, fn -> Money.allocate(Money.new(100, :USD), []) end
    assert_raise ArgumentError, fn -> Money.allocate(Money.new(100, :USD), [0, 0]) end
    assert_raise ArgumentError, fn -> Money.allocate(Money.new(100, :USD), [1, -1]) end
    assert_raise ArgumentError, fn -> Money.allocate(Money.new(100, :USD), [1, 1.5]) end
    assert_raise ArgumentError, fn -> Money.allocate(Money.new(100, :USD), :nope) end
  end