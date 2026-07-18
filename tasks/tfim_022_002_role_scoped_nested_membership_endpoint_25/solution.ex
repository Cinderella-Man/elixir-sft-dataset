  test "DELETE returns 401 with invalid token", %{store: store} do
    conn = delete_member(store, "team-1", "bob", "token-nobody")
    assert conn.status == 401
  end