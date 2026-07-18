  test "non-member cannot add", %{store: store} do
    conn = post_member(store, "team-1", "erin", "token-carol")
    assert conn.status == 403
  end