  test "POST invitations returns 401 with an invalid token", %{store: store} do
    body = Jason.encode!(%{"user_id" => "dave"})

    conn =
      :post
      |> conn("/api/teams/team-1/invitations", body)
      |> put_req_header("authorization", "Bearer token-nobody")
      |> put_req_header("content-type", "application/json")
      |> call(store)

    assert conn.status == 401
    assert json_body(conn)["error"] == "unauthorized"
  end