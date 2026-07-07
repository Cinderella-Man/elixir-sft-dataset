  test "allocate/2 distributes the remainder to the earliest parties" do
    parts = Money.allocate(Money.new(10, :USD), [1, 1, 1, 1])
    assert Enum.map(parts, & &1.amount) == [3, 3, 2, 2]
    assert Enum.sum(Enum.map(parts, & &1.amount)) == 10
  end