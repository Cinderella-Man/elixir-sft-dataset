  test "verify retrieves the token payload without consuming it", %{store: store} do
    {:ok, id} = OneTimeTokenStore.mint(store, %{user: "alice", action: :reset})

    assert {:ok, %{user: "alice", action: :reset}} = OneTimeTokenStore.verify(store, id)
    # Still available after verify
    assert {:ok, %{user: "alice", action: :reset}} = OneTimeTokenStore.verify(store, id)
  end