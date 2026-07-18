  test "split/2 raises when n is a non-integer number" do
    assert_raise ArgumentError, fn -> Money.split(Money.new(100, :USD), 3.0) end
    assert_raise ArgumentError, fn -> Money.split(Money.new(100, :USD), :three) end
  end