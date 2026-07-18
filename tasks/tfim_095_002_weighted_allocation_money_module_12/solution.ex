  test "allocate/2 with equal weights matches the canonical thirds example" do
    parts = Money.allocate(Money.new(1000, :USD), [1, 1, 1])
    assert Enum.map(parts, & &1.amount) == [334, 333, 333]
  end