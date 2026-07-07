  test "allocate/2 divides by weights that sum cleanly" do
    parts = Money.allocate(Money.new(100, :USD), [3, 7])
    assert Enum.map(parts, & &1.amount) == [30, 70]
    assert Enum.all?(parts, &(&1.currency == :USD))
  end