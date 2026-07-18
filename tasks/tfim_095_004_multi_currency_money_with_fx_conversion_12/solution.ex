  test "convert/3 USD to GBP" do
    assert Money.convert(Money.new(100, :USD), :GBP, @rates).amount == 80
  end