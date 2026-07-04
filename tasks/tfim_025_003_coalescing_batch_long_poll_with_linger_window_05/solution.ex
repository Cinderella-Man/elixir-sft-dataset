  test "returns 204 when timeout expires with no notifications", %{opts: opts} do
    conn = poll(opts, "user:1")
    assert conn.status == 204
    assert conn.resp_body == ""
  end