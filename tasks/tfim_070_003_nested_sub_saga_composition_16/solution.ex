  test "a compensation returning an error tuple is recorded without changing the failure" do
    result =
      Saga.new()
      |> Saga.step(:a, fn _ -> {:ok, 1} end, fn _ -> {:error, :comp_broke} end)
      |> Saga.step(:b, fn _ -> {:ok, 2} end, fn _ -> :ub end)
      |> Saga.step(:c, fn _ -> {:error, :real} end, fn _ -> :uc end)
      |> Saga.execute(%{})

    assert {:error, [:c], :real, comp} = result
    assert comp == [b: :ub, a: {:error, :comp_broke}]
  end