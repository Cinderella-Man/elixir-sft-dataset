  test "touch resets the inactivity timer", %{store: store} do
    {:ok, id} = SessionStore.create(store, %{user: "alice"})

    # Advance to 800ms — still alive
    Clock.advance(800)
    assert :ok = SessionStore.touch(store, id)

    # Advance another 800ms (total 1600ms from creation, 800ms from touch)
    Clock.advance(800)
    assert {:ok, %{user: "alice"}} = SessionStore.get(store, id)
  end