  test "split/2 of zero yields all zeros" do
    parts = Money.split(Money.new(0, :USD), 4)
    assert Enum.map(parts, & &1.amount) == [0, 0, 0, 0]
  end