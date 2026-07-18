  test "POST with malformed body returns 400", %{store: store} do
    v = version(store, "team-1")
    body = Jason.encode!(%{"wrong_field" => "carol"})

    conn =
      :post
      |> conn("/api/teams/team-1/members", body)
      |> put_req_header("authorization", "Bearer token-alice")
      |> put_req_header("content-type", "application/json")
      |> put_req_header("if-match", to_string(v))
      |> put_private(:team_store, store)
      |> TeamRouter.call(TeamRouter.init(store: store))

    assert conn.status == 400
  end