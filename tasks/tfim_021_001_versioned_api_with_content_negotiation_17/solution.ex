  test "v1 and v2 responses for the same user have different keys" do
    conn_v1 = call(:get, "/api/users/1", [{"accept-version", "v1"}])
    conn_v2 = call(:get, "/api/users/1", [{"accept-version", "v2"}])

    keys_v1 = json_body(conn_v1) |> Map.keys() |> Enum.sort()
    keys_v2 = json_body(conn_v2) |> Map.keys() |> Enum.sort()

    refute keys_v1 == keys_v2
  end