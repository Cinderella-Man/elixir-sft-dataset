  test "history/2 records every transition in order", %{sm: sm} do
    {:ok, :pending} = StateMachine.start(sm, "order:1")
    {:ok, :confirmed} = StateMachine.transition(sm, "order:1", :confirm)
    {:ok, :shipped} = StateMachine.transition(sm, "order:1", :ship)

    assert {:ok, [first, second]} = StateMachine.history(sm, "order:1")
    assert first.event == :confirm
    assert first.from_state == :pending
    assert first.to_state == :confirmed
    assert second.event == :ship
    assert second.from_state == :confirmed
    assert second.to_state == :shipped
  end