  test "TeamStore.add_member_safe returns conflict for duplicate at matching version", %{
    store: store
  } do
    v = version(store, "team-1")
    assert {:error, :conflict} = TeamStore.add_member_safe(store, "team-1", "alice", v)
  end