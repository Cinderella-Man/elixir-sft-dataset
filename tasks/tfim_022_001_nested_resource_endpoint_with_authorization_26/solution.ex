  test "TeamRouter resolves the store from its :store option without conn private", %{
    store: store
  } do
    conn =
      :get
      |> conn("/api/teams/team-1/members")
      |> put_req_header("authorization", "Bearer token-alice")
      |> TeamRouter.call(TeamRouter.init(store: store))

    assert conn.status == 200
    assert "alice" in Jason.decode!(conn.resp_body)["members"]
  end