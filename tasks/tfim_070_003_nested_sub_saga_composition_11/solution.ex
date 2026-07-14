  test "compensate_fn receives the accumulated context including completed results" do
    result =
      Saga.new()
      |> Saga.step(:a, fn ctx -> {:ok, ctx.seed * 2} end, fn ctx -> {:seen, ctx} end)
      |> Saga.step(:b, fn _ -> {:error, :stop} end, fn _ -> :ub end)
      |> Saga.execute(%{seed: 3})

    assert {:error, [:b], :stop, comp} = result
    assert {:seen, ctx} = comp[:a]
    assert ctx.seed == 3
    assert ctx.a == 6
  end