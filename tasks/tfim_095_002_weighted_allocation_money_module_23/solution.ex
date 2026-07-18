  test "new/2 produces a struct carrying exactly the amount and currency fields" do
    keys =
      Money.new(100, :USD)
      |> Map.from_struct()
      |> Map.keys()
      |> Enum.sort()

    assert keys == [:amount, :currency]
  end