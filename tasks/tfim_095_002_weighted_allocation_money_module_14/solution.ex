  test "allocate/2 handles negative amounts and still sums back" do
    parts = Money.allocate(Money.new(-10, :USD), [1, 1, 1])
    amounts = Enum.map(parts, & &1.amount)
    assert Enum.sum(amounts) == -10
    assert Enum.max(amounts) - Enum.min(amounts) <= 1
    assert amounts == [-4, -3, -3]
  end