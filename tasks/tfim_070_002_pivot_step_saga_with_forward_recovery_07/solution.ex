  test "compensable failure after a retriable step never compensates the retriable step" do
    result =
      Saga.new()
      |> Saga.step(:a, fn _ -> {:ok, 1} end, fn _ -> :ca end)
      |> Saga.retriable(:p, fn _ -> {:ok, :pivot} end, 2)
      |> Saga.step(:b, fn _ -> {:error, :boom} end, fn _ -> :cb end)
      |> Saga.execute(%{})

    assert {:error, :b, :boom, [a: :ca]} = result
  end