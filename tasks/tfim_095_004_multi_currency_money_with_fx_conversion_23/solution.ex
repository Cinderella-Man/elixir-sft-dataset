  test "split/2 shares sum back to the original for a negative amount" do
    parts = Money.split(Money.new(-1000, :USD), 3)
    amounts = Enum.map(parts, & &1.amount)
    assert length(amounts) == 3
    assert Enum.all?(parts, &(&1.currency == :USD))
    assert Enum.sum(amounts) == -1000
  end