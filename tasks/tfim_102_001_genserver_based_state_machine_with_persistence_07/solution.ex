  test "full happy path: pending → confirmed → shipped → delivered", %{sm: sm} do
    {:ok, _} = StateMachine.start(sm, "order:1")

    assert {:ok, :confirmed} = StateMachine.transition(sm, "order:1", :confirm)
    assert {:ok, :confirmed} = StateMachine.get_state(sm, "order:1")

    assert {:ok, :shipped} = StateMachine.transition(sm, "order:1", :ship)
    assert {:ok, :delivered} = StateMachine.transition(sm, "order:1", :deliver)

    assert {:ok, :delivered} = StateMachine.get_state(sm, "order:1")
  end