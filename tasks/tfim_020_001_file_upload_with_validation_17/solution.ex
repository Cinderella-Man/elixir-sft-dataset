  test "accepts JSON primitives (string)", %{opts: opts} do
    conn = call_upload(opts, "str.json", Jason.encode!("hello"))
    assert conn.status == 201
  end