  test "subtract/2 subtracts two same-currency values" do
    result = Money.subtract(Money.new(500, :USD), Money.new(200, :USD))
    assert result.amount == 300
    assert result.currency == :USD
  end