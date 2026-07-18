  test "POST returns 401 with invalid token", %{store: store} do
    body = Jason.encode!(%{"user_id" => "carol"})

    conn =
      :post
      |> conn("/api/teams/team-1/members", body)
      |> put_req_header("authorization", "Bearer token-nobody")
      |> put_req_header("content-type", "application/json")
      |> put_private(:team_store, store)
      |> TeamRouter.call(TeamRouter.init(store: store))

    assert conn.status == 401
    assert json_body(conn)["error"] == "unauthorized"
  end