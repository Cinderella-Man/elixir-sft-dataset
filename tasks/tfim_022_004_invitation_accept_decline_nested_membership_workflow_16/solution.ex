  test "POST invitations returns 400 for a body missing user_id", %{store: store} do
    body = Jason.encode!(%{"wrong_field" => "dave"})

    conn =
      :post
      |> conn("/api/teams/team-1/invitations", body)
      |> put_req_header("authorization", "Bearer token-alice")
      |> put_req_header("content-type", "application/json")
      |> call(store)

    assert conn.status == 400
    assert json_body(conn)["error"] == "bad_request"
  end