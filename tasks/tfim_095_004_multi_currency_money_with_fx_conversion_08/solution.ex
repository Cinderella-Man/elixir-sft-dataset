  test "split/2 distributes remainder and sums back" do
    parts = Money.split(Money.new(1000, :USD), 3)
    amounts = Enum.map(parts, & &1.amount)
    assert amounts == [334, 333, 333]
    assert Enum.sum(amounts) == 1000
  end