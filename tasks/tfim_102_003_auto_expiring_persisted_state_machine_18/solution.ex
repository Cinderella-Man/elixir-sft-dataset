  test "an invalid transition writes no row to the history", %{sm: sm} do
    {:ok, :pending} = StateMachine.start(sm, "order:novoid")

    assert {:error, :invalid_transition} = StateMachine.transition(sm, "order:novoid", :deliver)
    assert {:ok, []} = StateMachine.history(sm, "order:novoid")
  end