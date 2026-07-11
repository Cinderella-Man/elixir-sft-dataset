  test "stale expected_version is rejected and writes nothing", %{sm: sm} do
    {:ok, :pending, 0} = StateMachine.start(sm, "order:1")
    {:ok, :confirmed, 1} = StateMachine.transition(sm, "order:1", :confirm, 0)

    # Present the old version 0 again
    assert {:error, {:stale_version, 1}} =
             StateMachine.transition(sm, "order:1", :ship, 0)

    # State/version unchanged, and no extra row written
    assert {:ok, :confirmed, 1} = StateMachine.get_state(sm, "order:1")
    assert {:ok, [%{event: :confirm}]} = StateMachine.history(sm, "order:1")
  end