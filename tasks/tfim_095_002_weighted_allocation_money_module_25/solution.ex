  test "allocate/2 accepts zero weights and still pays remainder to the earliest party" do
    parts = Money.allocate(Money.new(10, :USD), [0, 1, 1, 1])
    amounts = Enum.map(parts, & &1.amount)
    assert amounts == [1, 3, 3, 3]
    assert Enum.sum(amounts) == 10
  end