  test "version check precedes validity check", %{sm: sm} do
    {:ok, :pending, 0} = StateMachine.start(sm, "order:1")
    {:ok, :confirmed, 1} = StateMachine.transition(sm, "order:1", :confirm, 0)

    # :deliver from :confirmed would be invalid, but the stale version wins
    assert {:error, {:stale_version, 1}} =
             StateMachine.transition(sm, "order:1", :deliver, 0)
  end