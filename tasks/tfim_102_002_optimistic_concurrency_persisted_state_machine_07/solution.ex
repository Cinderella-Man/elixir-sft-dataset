  test "full happy path increments version each step", %{sm: sm} do
    {:ok, :pending, 0} = StateMachine.start(sm, "order:1")

    assert {:ok, :confirmed, 1} = StateMachine.transition(sm, "order:1", :confirm, 0)
    assert {:ok, :shipped, 2} = StateMachine.transition(sm, "order:1", :ship, 1)
    assert {:ok, :delivered, 3} = StateMachine.transition(sm, "order:1", :deliver, 2)

    assert {:ok, :delivered, 3} = StateMachine.get_state(sm, "order:1")
  end