  test "multiply/2 rounds halves away from zero" do
    assert Money.multiply(Money.new(101, :USD), 0.5).amount == 51
    assert Money.multiply(Money.new(100, :USD), 0.005).amount == 1
  end