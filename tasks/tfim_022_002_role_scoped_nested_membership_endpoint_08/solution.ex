  test "owner can add a new member with default role", %{store: store} do
    conn = post_member(store, "team-1", "carol", "token-alice")
    assert conn.status == 201
    body = json_body(conn)
    assert body["added"] == "carol"
    assert body["role"] == "member"
    assert {:ok, "member"} = TeamStore.role_of(store, "team-1", "carol")
  end