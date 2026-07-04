  test "extension check is case-insensitive", %{opts: opts} do
    csv_content = "a,b\n1,2\n"
    conn = call_upload(opts, "DATA.CSV", csv_content)
    assert conn.status == 201

    json_content = Jason.encode!(%{"ok" => true})
    conn = call_upload(opts, "config.JSON", json_content)
    assert conn.status == 201
  end