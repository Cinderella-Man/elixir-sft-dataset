  test "valid JSON upload works", %{opts: opts} do
    conn = call_upload(opts, "data.json", Jason.encode!(%{"k" => "v"}))
    assert conn.status == 201
    assert json_body(conn)["content_type"] == "application/json"
  end