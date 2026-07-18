  test "accepts JSON arrays", %{opts: opts} do
    conn = call_upload(opts, "list.json", Jason.encode!([1, 2, 3]))
    assert conn.status == 201
  end