  test "split/2 distributes the remainder to the first parties" do
    parts = Money.split(Money.new(1000, :USD), 3)
    assert Enum.map(parts, & &1.amount) == [334, 333, 333]
  end