  test "empty saga returns original context with an empty journal" do
    assert {:ok, %{x: 1}, []} = Saga.new() |> Saga.execute(%{x: 1})
  end