  test "POST returns 404 for missing team before role checks", %{store: store} do
    conn = post_member(store, "ghost", "erin", "token-alice")
    assert conn.status == 404
  end