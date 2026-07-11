  test "invalid event returns :invalid_transition and does not change state", %{sm: sm} do
    {:ok, :pending} = StateMachine.start(sm, "order:1")
    assert {:error, :invalid_transition} = StateMachine.transition(sm, "order:1", :ship)
    assert {:ok, :pending} = StateMachine.get_state(sm, "order:1")
  end