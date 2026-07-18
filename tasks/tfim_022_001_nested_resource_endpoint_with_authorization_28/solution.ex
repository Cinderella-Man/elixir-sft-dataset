  test "authorization header without the Bearer scheme is unauthorized", %{store: store} do
    conn =
      :get
      |> conn("/api/teams/team-1/members")
      |> put_req_header("authorization", "Basic token-alice")
      |> put_private(:team_store, store)
      |> TeamRouter.call(TeamRouter.init(store: store))

    assert conn.status == 401
    assert Jason.decode!(conn.resp_body)["error"] == "unauthorized"
    assert conn.halted
  end