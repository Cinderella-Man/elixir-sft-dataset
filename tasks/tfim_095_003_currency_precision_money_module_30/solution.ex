  test "Money struct exposes exactly the amount and currency fields" do
    m = Money.new(12_345, :USD)
    assert m.__struct__ == Money
    assert m |> Map.from_struct() |> Map.keys() |> Enum.sort() == [:amount, :currency]
  end