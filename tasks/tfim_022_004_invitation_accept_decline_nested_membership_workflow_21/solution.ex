  test "POST accept returns 404 for a non-existent team", %{store: store} do
    conn = post_accept(store, "ghost-team", "dave", "token-dave")
    assert conn.status == 404
    assert json_body(conn)["error"] == "not_found"
  end