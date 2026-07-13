  test "cancellation from :confirmed", %{sm: sm} do
    {:ok, _} = StateMachine.start(sm, "order:3")
    {:ok, _} = StateMachine.transition(sm, "order:3", :confirm)
    assert {:ok, :cancelled} = StateMachine.transition(sm, "order:3", :cancel)
  end