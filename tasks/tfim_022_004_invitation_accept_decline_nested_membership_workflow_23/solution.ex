  test "POST decline returns 403 when declining someone else's invitation", %{store: store} do
    post_invite(store, "team-1", "dave", "token-alice")

    conn = post_decline(store, "team-1", "dave", "token-bob")
    assert conn.status == 403
    assert json_body(conn)["error"] == "forbidden"
  end