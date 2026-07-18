  test "POST accept returns 409 no_invitation when there is no pending invite", %{store: store} do
    conn = post_accept(store, "team-1", "dave", "token-dave")
    assert conn.status == 409
    assert json_body(conn)["error"] == "no_invitation"
  end