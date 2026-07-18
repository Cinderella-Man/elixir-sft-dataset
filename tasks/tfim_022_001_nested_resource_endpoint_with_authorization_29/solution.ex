  test "error responses carry the application/json content-type", %{store: store} do
    conns = [
      get_members(store, "no-such-team", "token-alice"),
      get_members(store, "team-1", "token-carol"),
      get_members(store, "team-1", "token-nobody"),
      post_member(store, "team-1", "bob", "token-alice")
    ]

    for conn <- conns do
      content_type = conn |> get_resp_header("content-type") |> List.first("")
      assert content_type =~ "application/json"
    end

    assert Enum.map(conns, & &1.status) == [404, 403, 401, 409]
  end