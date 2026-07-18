  test "invalid transition does not write to DB", %{sm: sm} do
    {:ok, _} = StateMachine.start(sm, "order:1")

    {:error, :invalid_transition} =
      StateMachine.transition(sm, "order:1", :ship)

    assert {:ok, []} = StateMachine.history(sm, "order:1")
  end