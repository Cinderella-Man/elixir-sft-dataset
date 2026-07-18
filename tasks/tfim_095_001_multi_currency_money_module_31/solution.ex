  test "multiply/2 rounds negative halves away from zero" do
    # -101 * 0.5 = -50.5 -> -51 (away from zero, not toward it)
    assert Money.multiply(Money.new(-101, :USD), 0.5).amount == -51
    # 101 * -0.5 = -50.5 -> -51
    assert Money.multiply(Money.new(101, :USD), -0.5).amount == -51
  end