  test "multiply/2 by an integer" do
    result = Money.multiply(Money.new(100, :USD), 3)
    assert result.amount == 300
    assert result.currency == :USD
  end