  test "nested sub-saga success stores the sub-context under the step name" do
    sub =
      Saga.new()
      |> Saga.step(:x, fn _ -> {:ok, 1} end, fn _ -> :ux end)
      |> Saga.step(:y, fn ctx -> {:ok, ctx.x + 1} end, fn _ -> :uy end)

    result =
      Saga.new()
      |> Saga.step(:before, fn _ -> {:ok, :b} end, fn _ -> :ub end)
      |> Saga.nest(:child, sub)
      |> Saga.execute(%{seed: 0})

    assert {:ok, ctx} = result
    assert ctx.before == :b
    assert ctx.child.x == 1
    assert ctx.child.y == 2
  end