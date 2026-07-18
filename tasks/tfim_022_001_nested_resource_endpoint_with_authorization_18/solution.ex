  test "POST returns 404 before 409 when team doesn't exist", %{store: store} do
    conn = post_member(store, "ghost-team", "bob", "token-alice")
    assert conn.status == 404
  end