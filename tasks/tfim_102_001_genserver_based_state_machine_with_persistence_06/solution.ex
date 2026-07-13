  test "get_state/2 reflects the current in-memory state", %{sm: sm} do
    {:ok, _} = StateMachine.start(sm, "order:1")
    {:ok, _} = StateMachine.transition(sm, "order:1", :confirm)
    assert {:ok, :confirmed} = StateMachine.get_state(sm, "order:1")
  end