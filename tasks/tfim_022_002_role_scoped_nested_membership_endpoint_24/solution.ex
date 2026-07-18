  test "DELETE returns 404 for missing team", %{store: store} do
    conn = delete_member(store, "ghost", "bob", "token-alice")
    assert conn.status == 404
  end