  test "mint returns a unique token id", %{store: store} do
    assert {:ok, id1} = OneTimeTokenStore.mint(store, %{action: :reset})
    assert {:ok, id2} = OneTimeTokenStore.mint(store, %{action: :invite})

    assert is_binary(id1)
    assert is_binary(id2)
    assert id1 != id2
  end