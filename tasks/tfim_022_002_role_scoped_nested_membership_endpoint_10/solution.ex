  test "owner can add a member with an explicit role", %{store: store} do
    conn = post_member(store, "team-1", "erin", "token-alice", "admin")
    assert conn.status == 201
    assert json_body(conn)["role"] == "admin"
    assert {:ok, "admin"} = TeamStore.role_of(store, "team-1", "erin")
  end