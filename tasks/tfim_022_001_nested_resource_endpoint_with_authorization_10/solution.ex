  test "POST returns 409 when member already exists", %{store: store} do
    conn = post_member(store, "team-1", "bob", "token-alice")

    assert conn.status == 409
    assert json_body(conn)["error"] == "conflict"
  end