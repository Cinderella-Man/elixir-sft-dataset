  test "returns 204 when timeout expires with no notification", %{opts: opts} do
    conn = poll(opts, "user:1", ["a"])
    assert conn.status == 204
    assert conn.resp_body == ""
  end