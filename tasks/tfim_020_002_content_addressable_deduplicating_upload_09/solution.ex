  test "extension check is case-insensitive", %{opts: opts} do
    conn = call_upload(opts, "DATA.CSV", "a,b\n1,2\n")
    assert conn.status == 201
  end