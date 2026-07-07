  test "add/2 and subtract/2 work on same currency" do
    assert Money.add(Money.new(100, :USD), Money.new(250, :USD)).amount == 350
    assert Money.subtract(Money.new(200, :USD), Money.new(500, :USD)).amount == -300
  end