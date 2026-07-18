  test "multiply/2 rounds halves away from zero" do
    # 101 * 0.5 = 50.5 -> 51
    assert Money.multiply(Money.new(101, :USD), 0.5).amount == 51
    # 100 * 0.005 = 0.5 -> 1
    assert Money.multiply(Money.new(100, :USD), 0.005).amount == 1
  end