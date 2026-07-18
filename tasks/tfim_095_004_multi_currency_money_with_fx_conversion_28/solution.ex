  test "multiply convert and total always store integer cents" do
    assert is_integer(Money.multiply(Money.new(101, :USD), 1.5).amount)
    assert is_integer(Money.convert(Money.new(37, :EUR), :GBP, @rates).amount)
    mixed = [Money.new(100, :USD), Money.new(33, :EUR), Money.new(7, :GBP)]
    assert is_integer(Money.total(mixed, :GBP, @rates).amount)
    assert is_integer(Money.total([], :EUR, @rates).amount)
  end