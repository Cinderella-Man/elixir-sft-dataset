  test "transition on unknown entity returns :not_found", %{sm: sm} do
    assert {:error, :not_found} = StateMachine.transition(sm, "cr:unknown", :submit)
  end