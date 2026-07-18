  test "default TTL is one hour when :default_ttl_ms is not given", %{store: _store} do
    {:ok, hourly} =
      OneTimeTokenStore.start_link(
        clock: &Clock.now/0,
        cleanup_interval_ms: :infinity
      )

    {:ok, id} = OneTimeTokenStore.mint(hourly, %{scope: :default})

    Clock.advance(3_599_999)
    assert {:ok, %{scope: :default}} = OneTimeTokenStore.verify(hourly, id)

    Clock.advance(2)
    assert {:error, :not_found} = OneTimeTokenStore.verify(hourly, id)
  end