  test "mint accepts per-token :ttl_ms override", %{store: store} do
    {:ok, short_id} = OneTimeTokenStore.mint(store, %{type: :short}, ttl_ms: 200)
    {:ok, long_id} = OneTimeTokenStore.mint(store, %{type: :long}, ttl_ms: 5_000)

    Clock.advance(300)

    assert {:error, :not_found} = OneTimeTokenStore.verify(store, short_id)
    assert {:ok, %{type: :long}} = OneTimeTokenStore.verify(store, long_id)
  end