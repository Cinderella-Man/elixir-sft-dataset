  test "subtract/2 can produce a negative result" do
    result = Money.subtract(Money.new(200, :USD), Money.new(500, :USD))
    assert result.amount == -300
  end