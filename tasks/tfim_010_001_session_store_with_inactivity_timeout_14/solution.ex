  test "get resets the inactivity timer", %{store: store} do
    {:ok, id} = SessionStore.create(store, %{user: "alice"})

    # Advance to 800ms, then get (resets timer)
    Clock.advance(800)
    assert {:ok, _} = SessionStore.get(store, id)

    # Advance another 800ms (total 1600ms from creation, 800ms from get)
    Clock.advance(800)
    assert {:ok, %{user: "alice"}} = SessionStore.get(store, id)
  end