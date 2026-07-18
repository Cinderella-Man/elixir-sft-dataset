  test "transition on unknown entity returns :not_found (before version check)", %{sm: sm} do
    assert {:error, :not_found} =
             StateMachine.transition(sm, "order:unknown", :confirm, 0)
  end