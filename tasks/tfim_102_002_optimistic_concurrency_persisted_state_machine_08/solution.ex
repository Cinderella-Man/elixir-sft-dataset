  test "cancellation from :pending and from :confirmed", %{sm: sm} do
    {:ok, :pending, 0} = StateMachine.start(sm, "order:2")
    assert {:ok, :cancelled, 1} = StateMachine.transition(sm, "order:2", :cancel, 0)

    {:ok, :pending, 0} = StateMachine.start(sm, "order:3")
    {:ok, :confirmed, 1} = StateMachine.transition(sm, "order:3", :confirm, 0)
    assert {:ok, :cancelled, 2} = StateMachine.transition(sm, "order:3", :cancel, 1)
  end