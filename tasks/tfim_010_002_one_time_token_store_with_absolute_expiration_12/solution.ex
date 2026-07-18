  test "verify does NOT extend the expiration (absolute, not sliding)", %{store: store} do
    {:ok, id} = OneTimeTokenStore.mint(store, %{user: "alice"})

    # Verify at 800ms — still alive
    Clock.advance(800)
    assert {:ok, _} = OneTimeTokenStore.verify(store, id)

    # Another 300ms later (total 1100ms from creation) — expired
    # In a sliding-window store, the verify at 800ms would have extended it.
    # Here it must NOT extend.
    Clock.advance(300)
    assert {:error, :not_found} = OneTimeTokenStore.verify(store, id)
  end