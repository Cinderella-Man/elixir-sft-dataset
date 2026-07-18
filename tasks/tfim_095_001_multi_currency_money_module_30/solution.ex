  test "split/2 of a negative amount still sums back to the original amount" do
    parts = Money.split(Money.new(-1000, :USD), 3)
    amounts = Enum.map(parts, & &1.amount)

    assert length(parts) == 3
    assert Enum.sum(amounts) == -1000
    assert Enum.all?(parts, &(&1.currency == :USD))
  end