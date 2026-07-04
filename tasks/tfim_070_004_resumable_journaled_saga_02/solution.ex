  test "execute returns final context and a chronological journal on success" do
    result =
      Saga.new()
      |> Saga.step(:a, fn _ -> {:ok, 1} end, fn _ -> :ua end)
      |> Saga.step(:b, fn ctx -> {:ok, ctx.a + 1} end, fn _ -> :ub end)
      |> Saga.execute(%{})

    assert {:ok, ctx, journal} = result
    assert ctx.a == 1 and ctx.b == 2
    assert journal == [{:completed, :a, 1}, {:completed, :b, 2}]
  end