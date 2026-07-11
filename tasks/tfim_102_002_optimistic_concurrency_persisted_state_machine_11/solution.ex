  test "invalid event at the correct version returns :invalid_transition", %{sm: sm} do
    {:ok, :pending, 0} = StateMachine.start(sm, "order:1")
    {:ok, :confirmed, 1} = StateMachine.transition(sm, "order:1", :confirm, 0)

    assert {:error, :invalid_transition} =
             StateMachine.transition(sm, "order:1", :deliver, 1)

    assert {:ok, :confirmed, 1} = StateMachine.get_state(sm, "order:1")
  end