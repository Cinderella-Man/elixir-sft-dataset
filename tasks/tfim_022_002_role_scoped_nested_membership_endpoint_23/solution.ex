  test "plain member cannot remove", %{store: store} do
    conn = delete_member(store, "team-1", "dave", "token-bob")
    assert conn.status == 403
  end