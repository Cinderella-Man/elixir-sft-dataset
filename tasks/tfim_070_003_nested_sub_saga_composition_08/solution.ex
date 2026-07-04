  test "sub-saga can read outer context values" do
    sub =
      Saga.new()
      |> Saga.step(:derived, fn ctx -> {:ok, ctx.base * 10} end, fn _ -> nil end)

    result =
      Saga.new()
      |> Saga.step(:base, fn _ -> {:ok, 5} end, fn _ -> nil end)
      |> Saga.nest(:child, sub)
      |> Saga.execute(%{})

    assert {:ok, ctx} = result
    assert ctx.child.derived == 50
  end