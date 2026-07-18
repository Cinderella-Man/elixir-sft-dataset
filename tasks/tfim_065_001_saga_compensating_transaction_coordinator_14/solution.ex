  test "a step result overwrites a pre-existing context key of the same name" do
    saga =
      Saga.new()
      |> Saga.step(:order_id, ok_action(:order_id, 99), comp(:order_id))
      |> Saga.step(:next, fn ctx -> {:ok, ctx.order_id} end, comp(:next))

    assert {:ok, ctx} = Saga.execute(saga, %{order_id: 42})

    assert ctx.order_id == 99
    assert ctx.next == 99
  end