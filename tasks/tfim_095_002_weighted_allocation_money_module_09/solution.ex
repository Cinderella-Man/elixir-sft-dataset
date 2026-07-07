  test "multiply/2 preserves currency" do
    assert Money.multiply(Money.new(500, :EUR), 2).currency == :EUR
  end