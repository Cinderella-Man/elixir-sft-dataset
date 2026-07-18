  test "POST missing user_id returns 400", %{store: store} do
    conn =
      :post
      |> conn("/api/teams/team-1/members", Jason.encode!(%{"wrong" => "x"}))
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer token-alice")
      |> put_private(:team_store, store)
      |> TeamRouter.call(TeamRouter.init(store: store))

    assert conn.status == 400
  end