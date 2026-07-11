  test "get_state/2 reflects current state and version", %{sm: sm} do
    {:ok, :pending, 0} = StateMachine.start(sm, "order:1")
    {:ok, :confirmed, 1} = StateMachine.transition(sm, "order:1", :confirm, 0)
    assert {:ok, :confirmed, 1} = StateMachine.get_state(sm, "order:1")
  end