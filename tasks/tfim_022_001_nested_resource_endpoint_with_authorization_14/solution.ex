  test "operations on team-1 do not affect team-2", %{store: store} do
    # Exhaust interactions with team-1
    post_member(store, "team-1", "carol", "token-alice")

    # team-2 is unaffected — carol is still the only member
    conn = get_members(store, "team-2", "token-carol")
    assert conn.status == 200
    members = json_body(conn)["members"]
    assert members == ["carol"]
  end