  test "manual :expire from :pending is a valid transition", %{sm: sm} do
    {:ok, :pending} = StateMachine.start(sm, "order:m")
    assert {:ok, :cancelled} = StateMachine.transition(sm, "order:m", :expire)
  end