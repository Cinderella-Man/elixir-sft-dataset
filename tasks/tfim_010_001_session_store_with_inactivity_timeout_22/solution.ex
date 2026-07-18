  test "session with minimal timeout (1ms)", %{store: _store} do
    # Override timeout per-test by starting a new store
    {:ok, short} =
      SessionStore.start_link(
        clock: &Clock.now/0,
        timeout_ms: 1,
        cleanup_interval_ms: :infinity
      )

    {:ok, id} = SessionStore.create(short, %{flash: true})
    assert {:ok, _} = SessionStore.get(short, id)

    Clock.advance(2)
    assert {:error, :not_found} = SessionStore.get(short, id)
  end