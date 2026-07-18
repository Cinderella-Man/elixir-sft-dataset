  test "chained operations behave consistently" do
    total =
      Money.from_major(10.00, :USD)
      |> Money.add(Money.new(500, :USD))
      |> Money.multiply(2)

    assert total.amount == 3000
    assert Money.to_string(total) == "30.00 USD"
  end