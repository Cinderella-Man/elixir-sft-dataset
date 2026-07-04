  test "plain member cannot add", %{store: store} do
    conn = post_member(store, "team-1", "carol", "token-bob")
    assert conn.status == 403
    assert json_body(conn)["error"] == "forbidden"
  end