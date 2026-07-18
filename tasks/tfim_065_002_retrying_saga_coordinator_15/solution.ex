  test "the starting context is preserved alongside the merged step results" do
    saga =
      RetrySaga.new()
      |> RetrySaga.step(:reserve, flaky_action(:reserve, 1, :r1), comp(:reserve), max_attempts: 2)
      |> RetrySaga.step(:charge, fn ctx -> {:ok, {ctx.order_id, ctx.reserve}} end, comp(:charge))

    assert {:ok, ctx} = RetrySaga.execute(saga, %{order_id: 42, extra: :kept})
    assert ctx == %{order_id: 42, extra: :kept, reserve: :r1, charge: {42, :r1}}
  end