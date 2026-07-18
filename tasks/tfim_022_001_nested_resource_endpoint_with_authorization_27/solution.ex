  test "unknown route without credentials is rejected by AuthPlug with 401", %{store: store} do
    conn =
      :get
      |> conn("/api/teams/team-1/nonsense")
      |> TeamRouter.call(TeamRouter.init(store: store))

    assert conn.status == 401
    assert Jason.decode!(conn.resp_body)["error"] == "unauthorized"
    assert conn.halted
  end