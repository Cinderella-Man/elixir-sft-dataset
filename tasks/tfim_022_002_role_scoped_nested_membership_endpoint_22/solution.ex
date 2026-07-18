  test "removing a non-member returns 404", %{store: store} do
    conn = delete_member(store, "team-1", "carol", "token-alice")
    assert conn.status == 404
  end