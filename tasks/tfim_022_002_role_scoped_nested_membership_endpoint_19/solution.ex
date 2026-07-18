  test "admin can remove a plain member", %{store: store} do
    conn = delete_member(store, "team-1", "bob", "token-dave")
    assert conn.status == 200
    refute TeamStore.is_member?(store, "team-1", "bob")
  end