  test "GET invitations returns 200 with an empty list initially", %{store: store} do
    conn = get_invitations(store, "team-1", "token-alice")
    assert conn.status == 200
    assert json_body(conn)["invitations"] == []
  end