  test "history entries expose atom lifecycle values and a DateTime inserted_at", %{sm: sm} do
    {:ok, :pending} = StateMachine.start(sm, "order:dt")
    {:ok, :confirmed} = StateMachine.transition(sm, "order:dt", :confirm)

    assert {:ok, [entry]} = StateMachine.history(sm, "order:dt")
    assert %DateTime{} = entry.inserted_at
    assert is_atom(entry.event)
    assert is_atom(entry.from_state)
    assert is_atom(entry.to_state)
  end