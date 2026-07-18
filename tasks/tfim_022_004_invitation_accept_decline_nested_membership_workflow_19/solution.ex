  test "POST accept returns 403 when accepting someone else's invitation", %{store: store} do
    post_invite(store, "team-1", "dave", "token-alice")

    conn = post_accept(store, "team-1", "dave", "token-bob")
    assert conn.status == 403
    assert json_body(conn)["error"] == "forbidden"
  end