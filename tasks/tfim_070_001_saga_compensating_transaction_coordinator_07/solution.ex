  test "failed step receives context enriched by prior successful steps" do
    Saga.new()
    |> Saga.step(:first, fn _ctx -> {:ok, 42} end, fn _ctx -> nil end)
    |> Saga.step(
      :second,
      fn ctx ->
        track(:saw_context, ctx)
        {:error, :oops}
      end,
      fn _ctx -> nil end
    )
    |> Saga.execute(%{initial: true})

    [ctx] = tracked(:saw_context)
    assert ctx.initial == true
    assert ctx.first == 42
  end