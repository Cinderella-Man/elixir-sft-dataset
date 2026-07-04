  test "resume with an empty journal behaves like execute" do
    saga =
      Saga.new()
      |> Saga.step(:a, fn _ -> {:ok, 1} end, fn _ -> :ua end)
      |> Saga.step(:b, fn _ -> {:ok, 2} end, fn _ -> :ub end)

    assert Saga.resume(saga, %{}, []) == Saga.execute(saga, %{})
  end