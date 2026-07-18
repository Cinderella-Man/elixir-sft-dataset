  test "token with minimal TTL (1ms)", %{store: _store} do
    {:ok, short} =
      OneTimeTokenStore.start_link(
        clock: &Clock.now/0,
        default_ttl_ms: 1,
        cleanup_interval_ms: :infinity
      )

    {:ok, id} = OneTimeTokenStore.mint(short, %{flash: true})
    assert {:ok, _} = OneTimeTokenStore.verify(short, id)

    Clock.advance(2)
    assert {:error, :not_found} = OneTimeTokenStore.verify(short, id)
  end