  test "multiply/2 rounds to whole minor units" do
    assert Money.multiply(Money.new(101, :USD), 0.5).amount == 51
    assert Money.multiply(Money.new(100, :JPY), 3).amount == 300
  end