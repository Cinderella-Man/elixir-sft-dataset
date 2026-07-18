  test "split/2 divides evenly when it divides cleanly" do
    parts = Money.split(Money.new(900, :USD), 3)
    assert Enum.map(parts, & &1.amount) == [300, 300, 300]
  end