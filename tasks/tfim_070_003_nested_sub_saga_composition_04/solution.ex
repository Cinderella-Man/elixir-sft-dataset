  test "a later outer failure fully compensates a completed nested sub-saga in reverse" do
    sub =
      Saga.new()
      |> Saga.step(:x, fn _ -> {:ok, 1} end, fn _ -> :ux end)
      |> Saga.step(:y, fn _ -> {:ok, 2} end, fn _ -> :uy end)

    result =
      Saga.new()
      |> Saga.nest(:child, sub)
      |> Saga.step(:c, fn _ -> {:error, :boom} end, fn _ -> :uc end)
      |> Saga.execute(%{})

    assert {:error, [:c], :boom, comp} = result
    assert comp == [child: [y: :uy, x: :ux]]
  end