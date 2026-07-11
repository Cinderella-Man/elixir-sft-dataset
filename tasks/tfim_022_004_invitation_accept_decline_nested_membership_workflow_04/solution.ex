  test "GET members returns 401 with missing auth header", %{store: store} do
    conn =
      :get
      |> conn("/api/teams/team-1/members")
      |> call(store)

    assert conn.status == 401
    assert json_body(conn)["error"] == "unauthorized"
  end