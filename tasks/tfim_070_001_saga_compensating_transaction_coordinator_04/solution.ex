  test "returns error tuple when a step fails" do
    result =
      Saga.new()
      |> Saga.step(:a, fn _ctx -> {:ok, 1} end, fn _ctx -> nil end)
      |> Saga.step(:b, fn _ctx -> {:error, :boom} end, fn _ctx -> nil end)
      |> Saga.step(:c, fn _ctx -> {:ok, 3} end, fn _ctx -> nil end)
      |> Saga.execute(%{})

    assert {:error, :b, :boom, _compensation_results} = result
  end