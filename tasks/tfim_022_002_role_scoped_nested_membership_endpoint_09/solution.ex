  test "admin can add a new member", %{store: store} do
    conn = post_member(store, "team-1", "erin", "token-dave")
    assert conn.status == 201
    assert TeamStore.is_member?(store, "team-1", "erin")
  end