  test "AuthPlug resolves the store from its init option alone", %{store: store} do
    conn =
      :get
      |> conn("/api/teams/team-1/members")
      |> put_req_header("authorization", "Bearer token-alice")
      |> AuthPlug.call(AuthPlug.init(store: store))

    refute conn.halted
    assert conn.assigns.current_user == "alice"
  end