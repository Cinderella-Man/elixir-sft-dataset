  test "history/2 is scoped per entity", %{sm: sm} do
    {:ok, _} = StateMachine.start(sm, "order:A")
    {:ok, _} = StateMachine.start(sm, "order:B")
    {:ok, _} = StateMachine.transition(sm, "order:A", :confirm)
    {:ok, _} = StateMachine.transition(sm, "order:B", :cancel)

    assert {:ok, [%{event: :confirm}]} = StateMachine.history(sm, "order:A")
    assert {:ok, [%{event: :cancel}]} = StateMachine.history(sm, "order:B")
  end