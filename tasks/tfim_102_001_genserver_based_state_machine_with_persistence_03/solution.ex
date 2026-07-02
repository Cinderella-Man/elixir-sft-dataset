  test "start/2 for the same entity twice returns the same state", %{sm: sm} do
    {:ok, :pending} = StateMachine.start(sm, "order:1")
    assert {:ok, :pending} = StateMachine.start(sm, "order:1")
  end