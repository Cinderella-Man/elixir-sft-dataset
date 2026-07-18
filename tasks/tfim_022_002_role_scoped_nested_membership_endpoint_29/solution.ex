  test "AuthPlug.init/1 output drives authentication when passed to call/2",
       %{store: store} do
    opts = AuthPlug.init(store: store)
    assert opts == [store: store]

    authed =
      :get
      |> conn("/api/teams/team-1/members")
      |> put_req_header("authorization", "Bearer token-alice")
      |> AuthPlug.call(opts)

    refute authed.halted
    assert authed.assigns[:current_user] == "alice"

    rejected =
      :get
      |> conn("/api/teams/team-1/members")
      |> AuthPlug.call(opts)

    assert rejected.halted
    assert rejected.status == 401
  end