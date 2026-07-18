  test "admin cannot remove an owner", %{store: store} do
    conn = delete_member(store, "team-1", "alice", "token-dave")
    assert conn.status == 403
    assert json_body(conn)["error"] == "forbidden"
    assert TeamStore.is_member?(store, "team-1", "alice")
  end