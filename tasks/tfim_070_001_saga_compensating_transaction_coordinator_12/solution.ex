  test "single successful step returns context with its result" do
    assert {:ok, %{only: :result}} =
             Saga.new()
             |> Saga.step(:only, fn _ctx -> {:ok, :result} end, fn _ctx -> nil end)
             |> Saga.execute(%{})
  end