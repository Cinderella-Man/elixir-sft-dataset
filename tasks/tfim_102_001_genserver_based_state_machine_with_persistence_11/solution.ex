  test "transitioning a terminal state is invalid", %{sm: sm} do
    {:ok, _} = StateMachine.start(sm, "order:1")
    {:ok, _} = StateMachine.transition(sm, "order:1", :cancel)

    assert {:error, :invalid_transition} =
             StateMachine.transition(sm, "order:1", :confirm)

    assert {:ok, :cancelled} = StateMachine.get_state(sm, "order:1")
  end