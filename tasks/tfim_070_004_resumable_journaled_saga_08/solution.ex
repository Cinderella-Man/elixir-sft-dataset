  test "all compensations run even if one raises" do
    result =
      Saga.new()
      |> Saga.step(:a, fn _ -> {:ok, 1} end, fn _ -> raise "boom" end)
      |> Saga.step(:b, fn _ -> {:ok, 2} end, fn _ -> :ub end)
      |> Saga.step(:c, fn _ -> {:error, :fail} end, fn _ -> :uc end)
      |> Saga.execute(%{})

    assert {:error, :c, :fail, comp, _journal} = result
    assert comp[:b] == :ub
    assert match?({:exception, _, _}, comp[:a])
  end