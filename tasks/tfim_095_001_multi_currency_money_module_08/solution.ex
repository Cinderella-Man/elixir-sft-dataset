  test "add/2 handles negative operands" do
    result = Money.add(Money.new(100, :USD), Money.new(-30, :USD))
    assert result.amount == 70
    assert result.currency == :USD
  end