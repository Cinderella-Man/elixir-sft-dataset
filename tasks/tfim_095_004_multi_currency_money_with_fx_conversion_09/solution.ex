  test "split/2 raises when n is not a positive integer" do
    assert_raise ArgumentError, fn -> Money.split(Money.new(100, :USD), 0) end
  end