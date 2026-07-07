  test "convert/3 EUR to USD" do
    assert Money.convert(Money.new(100, :EUR), :USD, @rates).amount == 110
  end