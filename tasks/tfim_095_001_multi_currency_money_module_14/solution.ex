  test "multiply/2 by a float" do
    result = Money.multiply(Money.new(100, :USD), 0.1)
    assert result.amount == 10
    assert result.currency == :USD
  end