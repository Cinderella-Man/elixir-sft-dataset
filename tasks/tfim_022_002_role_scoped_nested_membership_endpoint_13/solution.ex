  test "POST duplicate member returns 409", %{store: store} do
    conn = post_member(store, "team-1", "bob", "token-alice")
    assert conn.status == 409
    assert json_body(conn)["error"] == "conflict"
  end