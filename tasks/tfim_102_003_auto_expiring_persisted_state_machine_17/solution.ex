  test "cancel from :confirmed yields :cancelled and records the transition", %{sm: sm} do
    {:ok, :pending} = StateMachine.start(sm, "order:cancel-c")
    {:ok, :confirmed} = StateMachine.transition(sm, "order:cancel-c", :confirm)

    assert {:ok, :cancelled} = StateMachine.transition(sm, "order:cancel-c", :cancel)
    assert {:ok, :cancelled} = StateMachine.get_state(sm, "order:cancel-c")

    assert {:ok, [_confirm, %{event: :cancel, from_state: :confirmed, to_state: :cancelled}]} =
             StateMachine.history(sm, "order:cancel-c")
  end