  test "executes all steps and returns enriched context on success" do
    result =
      Saga.new()
      |> Saga.step(:reserve, fn ctx -> {:ok, "reservation:#{ctx.user}"} end, fn _ctx ->
        :cancel
      end)
      |> Saga.step(:charge, fn ctx -> {:ok, "charge:#{ctx.reserve}"} end, fn _ctx -> :refund end)
      |> Saga.step(:notify, fn ctx -> {:ok, "notified:#{ctx.charge}"} end, fn _ctx ->
        :undo_notify
      end)
      |> Saga.execute(%{user: "alice"})

    assert {:ok, ctx} = result
    assert ctx.reserve == "reservation:alice"
    assert ctx.charge == "charge:reservation:alice"
    assert ctx.notify == "notified:charge:reservation:alice"
  end