  test "POST newly added member appears in subsequent GET", %{store: store} do
    post_member(store, "team-1", "carol", "token-alice")

    conn = get_members(store, "team-1", "token-alice")
    assert "carol" in json_body(conn)["members"]
  end