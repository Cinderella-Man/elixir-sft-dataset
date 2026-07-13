  test "invalid event returns :invalid_transition and does not change state", %{sm: sm} do
    {:ok, _} = StateMachine.start(sm, "order:1")
    {:ok, _} = StateMachine.transition(sm, "order:1", :confirm)

    # :ship from :confirmed is valid, but :deliver from :confirmed is not
    assert {:error, :invalid_transition} =
             StateMachine.transition(sm, "order:1", :deliver)

    # State must be unchanged
    assert {:ok, :confirmed} = StateMachine.get_state(sm, "order:1")
  end