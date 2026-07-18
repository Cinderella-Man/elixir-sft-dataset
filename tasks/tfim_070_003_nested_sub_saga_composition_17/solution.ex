  test "a step after a nested step reads the sub-saga context under the nest name" do
    sub =
      Saga.new()
      |> Saga.step(:x, fn _ -> {:ok, 7} end, fn _ -> :ux end)

    result =
      Saga.new()
      |> Saga.step(:seedy, fn _ -> {:ok, 2} end, fn _ -> :us end)
      |> Saga.nest(:child, sub)
      |> Saga.step(:total, fn ctx -> {:ok, ctx.child.x * ctx.seedy} end, fn _ -> :ut end)
      |> Saga.execute(%{})

    assert {:ok, ctx} = result
    assert ctx.total == 14
    assert ctx.child.seedy == 2
  end