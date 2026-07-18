  test "history/2 records event, states, and version in order", %{sm: sm} do
    {:ok, :pending, 0} = StateMachine.start(sm, "order:1")
    {:ok, :confirmed, 1} = StateMachine.transition(sm, "order:1", :confirm, 0)
    {:ok, :shipped, 2} = StateMachine.transition(sm, "order:1", :ship, 1)

    assert {:ok, [first, second]} = StateMachine.history(sm, "order:1")

    assert first.event == :confirm
    assert first.from_state == :pending
    assert first.to_state == :confirmed
    assert first.version == 1

    assert second.event == :ship
    assert second.from_state == :confirmed
    assert second.to_state == :shipped
    assert second.version == 2
  end