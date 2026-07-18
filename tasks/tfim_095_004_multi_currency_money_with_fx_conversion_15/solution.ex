  test "convert/3 raises when a currency is missing from the rate table" do
    assert_raise ArgumentError, fn -> Money.convert(Money.new(100, :JPY), :USD, @rates) end
    assert_raise ArgumentError, fn -> Money.convert(Money.new(100, :USD), :JPY, @rates) end
  end