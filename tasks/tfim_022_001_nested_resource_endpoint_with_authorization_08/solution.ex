  test "POST returns 201 when adding a new member", %{store: store} do
    conn = post_member(store, "team-1", "carol", "token-alice")

    assert conn.status == 201
    body = json_body(conn)
    assert body["added"] == "carol"

    # Verify carol is now actually in team-1
    assert TeamStore.is_member?(store, "team-1", "carol")
  end