  test "owner can remove an admin", %{store: store} do
    conn = delete_member(store, "team-1", "dave", "token-alice")
    assert conn.status == 200
    refute TeamStore.is_member?(store, "team-1", "dave")
  end