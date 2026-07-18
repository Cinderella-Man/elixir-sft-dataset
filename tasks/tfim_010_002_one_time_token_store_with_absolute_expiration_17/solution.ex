  test "expired tokens are cleaned up by sweep", %{store: store} do
    ids =
      for i <- 1..100 do
        {:ok, id} = OneTimeTokenStore.mint(store, %{index: i})
        id
      end

    Clock.advance(1_100)

    send(store, :cleanup)

    # The call both waits for the sweep to be processed and shows no token survived.
    assert OneTimeTokenStore.active_count(store) == 0

    for id <- ids do
      assert {:error, :not_found} = OneTimeTokenStore.verify(store, id)
    end
  end