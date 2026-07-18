  test "GET returns 404 before 403 when team doesn't exist and user is anyone", %{store: store} do
    # Even for a valid user, a non-existent team is 404, not 403
    conn = get_members(store, "ghost-team", "token-alice")
    assert conn.status == 404
  end