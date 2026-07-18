  test "cancel from :pending yields :cancelled and records the transition", %{sm: sm} do
    {:ok, :pending} = StateMachine.start(sm, "order:cancel-p")

    assert {:ok, :cancelled} = StateMachine.transition(sm, "order:cancel-p", :cancel)
    assert {:ok, :cancelled} = StateMachine.get_state(sm, "order:cancel-p")

    assert {:ok, [%{event: :cancel, from_state: :pending, to_state: :cancelled}]} =
             StateMachine.history(sm, "order:cancel-p")
  end