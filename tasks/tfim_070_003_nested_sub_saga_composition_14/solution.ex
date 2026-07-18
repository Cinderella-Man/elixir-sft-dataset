  test "a raising compensation inside a nested saga still lets sibling compensations run" do
    sub =
      Saga.new()
      |> Saga.step(:x, fn _ -> {:ok, 1} end, fn _ -> :ux end)
      |> Saga.step(:y, fn _ -> {:ok, 2} end, fn _ -> raise "inner boom" end)

    result =
      Saga.new()
      |> Saga.step(:a, fn _ -> {:ok, :aa} end, fn _ -> :ua end)
      |> Saga.nest(:child, sub)
      |> Saga.step(:last, fn _ -> {:error, :late} end, fn _ -> :ulast end)
      |> Saga.execute(%{})

    assert {:error, [:last], :late, comp} = result
    assert [{:child, inner}, {:a, :ua}] = comp
    assert match?({:exception, %RuntimeError{message: "inner boom"}, _}, inner[:y])
    assert inner[:x] == :ux
  end