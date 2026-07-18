  test "mint works with various payload types", %{store: store} do
    {:ok, id1} = OneTimeTokenStore.mint(store, "just a string")
    {:ok, id2} = OneTimeTokenStore.mint(store, [1, 2, 3])
    {:ok, id3} = OneTimeTokenStore.mint(store, {:tuple, :data})

    assert {:ok, "just a string"} = OneTimeTokenStore.redeem(store, id1)
    assert {:ok, [1, 2, 3]} = OneTimeTokenStore.redeem(store, id2)
    assert {:ok, {:tuple, :data}} = OneTimeTokenStore.redeem(store, id3)
  end