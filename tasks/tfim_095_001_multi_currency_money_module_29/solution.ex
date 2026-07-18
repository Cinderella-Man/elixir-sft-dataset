  test "chained operations behave consistently" do
    total =
      Money.new(1000, :USD)
      |> Money.add(Money.new(500, :USD))
      |> Money.subtract(Money.new(200, :USD))
      |> Money.multiply(2)

    assert total.amount == 2600
    assert total.currency == :USD

    parts = Money.split(total, 3)
    assert Enum.sum(Enum.map(parts, & &1.amount)) == 2600
  end