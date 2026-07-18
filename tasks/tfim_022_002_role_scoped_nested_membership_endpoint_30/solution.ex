  test "router runs AuthPlug.init/1 at request time", %{store: store} do
    # A full request exercises the runtime-initialized AuthPlug pipeline; a
    # gutted init/1 would raise here rather than authenticate cleanly.
    conn = get_members(store, "team-1", "token-alice")
    assert conn.status == 200
    assert member(conn, "alice")["role"] == "owner"
  end