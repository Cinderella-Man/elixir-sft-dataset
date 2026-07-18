  test "server is reachable through its registered :name", %{store: _store} do
    name = :one_time_token_store_named_audit

    {:ok, _pid} =
      OneTimeTokenStore.start_link(
        name: name,
        clock: &Clock.now/0,
        default_ttl_ms: 1_000,
        cleanup_interval_ms: :infinity
      )

    {:ok, id} = OneTimeTokenStore.mint(name, %{via: :name})

    assert {:ok, %{via: :name}} = OneTimeTokenStore.verify(name, id)
    assert {:ok, %{via: :name}} = OneTimeTokenStore.redeem(name, id)
  end