  test "cancellation from :pending", %{sm: sm} do
    {:ok, _} = StateMachine.start(sm, "order:2")
    assert {:ok, :cancelled} = StateMachine.transition(sm, "order:2", :cancel)
  end