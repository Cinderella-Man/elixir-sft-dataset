  test "start/2 twice returns the same state and version", %{sm: sm} do
    {:ok, :pending, 0} = StateMachine.start(sm, "order:1")
    assert {:ok, :pending, 0} = StateMachine.start(sm, "order:1")
  end