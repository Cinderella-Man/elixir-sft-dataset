  test "executes all compensable steps and threads enriched context" do
    result =
      Saga.new()
      |> Saga.step(:reserve, fn ctx -> {:ok, "res:#{ctx.user}"} end, fn _ -> :cancel end)
      |> Saga.step(:charge, fn ctx -> {:ok, "chg:#{ctx.reserve}"} end, fn _ -> :refund end)
      |> Saga.execute(%{user: "alice"})

    assert {:ok, ctx} = result
    assert ctx.reserve == "res:alice"
    assert ctx.charge == "chg:res:alice"
  end