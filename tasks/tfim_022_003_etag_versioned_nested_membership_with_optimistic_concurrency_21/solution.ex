  test "operations on team-1 do not affect team-2", %{store: store} do
    v = version(store, "team-1")
    post_member(store, "team-1", "carol", "token-alice", to_string(v))

    conn = get_members(store, "team-2", "token-carol")
    assert conn.status == 200
    assert json_body(conn)["members"] == ["carol"]
  end