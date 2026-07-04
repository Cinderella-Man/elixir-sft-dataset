  test "empty saga returns the original context unchanged" do
    assert {:ok, %{x: 1}} = Saga.new() |> Saga.execute(%{x: 1})
  end