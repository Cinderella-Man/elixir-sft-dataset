  test "split/2 raises when n is a non-integer or negative" do
    assert_raise ArgumentError, fn -> Money.split(Money.new(100, :USD), 1.5) end
    assert_raise ArgumentError, fn -> Money.split(Money.new(100, :USD), 2.0) end
    assert_raise ArgumentError, fn -> Money.split(Money.new(100, :USD), -3) end
    assert_raise ArgumentError, fn -> Money.split(Money.new(100, :USD), :two) end
  end