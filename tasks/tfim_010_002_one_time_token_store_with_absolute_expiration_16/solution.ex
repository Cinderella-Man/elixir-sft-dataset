  test "active_count reflects only non-expired, non-redeemed tokens", %{store: store} do
    {:ok, id1} = OneTimeTokenStore.mint(store, %{n: 1})
    {:ok, _id2} = OneTimeTokenStore.mint(store, %{n: 2})
    {:ok, _id3} = OneTimeTokenStore.mint(store, %{n: 3})

    assert OneTimeTokenStore.active_count(store) == 3

    # Redeem one
    OneTimeTokenStore.redeem(store, id1)
    assert OneTimeTokenStore.active_count(store) == 2

    # Expire the remaining two
    Clock.advance(1_001)
    assert OneTimeTokenStore.active_count(store) == 0
  end