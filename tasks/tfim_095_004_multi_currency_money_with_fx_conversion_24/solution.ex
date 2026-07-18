  test "multiply/2 rounds negative halves away from zero" do
    assert Money.multiply(Money.new(-101, :USD), 0.5).amount == -51
    assert Money.multiply(Money.new(-1, :USD), 0.5).amount == -1
    assert Money.multiply(Money.new(1, :USD), 0.5).amount == 1
  end