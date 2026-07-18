  test "multiply/2 by zero yields zero" do
    assert Money.multiply(Money.new(999, :USD), 0).amount == 0
  end