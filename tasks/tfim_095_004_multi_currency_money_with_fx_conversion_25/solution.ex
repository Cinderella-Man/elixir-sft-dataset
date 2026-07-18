  test "split/2 raises for a float n and for a negative n" do
    assert_raise ArgumentError, fn -> Money.split(Money.new(100, :USD), 2.0) end
    assert_raise ArgumentError, fn -> Money.split(Money.new(100, :USD), -3) end
    assert_raise ArgumentError, fn -> Money.split(Money.new(100, :USD), :two) end
  end