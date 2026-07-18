  test "POST returns 401 with invalid token", %{store: store} do
    conn = post_member(store, "team-1", "erin", "token-nobody")
    assert conn.status == 401
  end