  test "expired sessions are cleaned up by sweep", %{store: store} do
    # Create 100 sessions
    ids =
      for i <- 1..100 do
        {:ok, id} = SessionStore.create(store, %{index: i})
        id
      end

    # Advance past all timeouts
    Clock.advance(1_100)

    # Trigger cleanup
    send(store, :cleanup)
    await_cleanup(store)

    # Every swept session is unreachable through the public API
    for id <- ids do
      assert {:error, :not_found} = SessionStore.get(store, id)
    end
  end