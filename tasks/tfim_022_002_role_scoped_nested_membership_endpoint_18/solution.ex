  test "owner can remove a member", %{store: store} do
    conn = delete_member(store, "team-1", "bob", "token-alice")
    assert conn.status == 200
    assert json_body(conn)["removed"] == "bob"
    refute TeamStore.is_member?(store, "team-1", "bob")
  end