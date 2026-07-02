  test "returns 204 when timeout expires with no notifications", %{opts: opts} do
    # Poll with the short 500ms timeout — nobody publishes anything
    conn = poll(opts, "user:1")

    assert conn.status == 204
    assert conn.resp_body == ""
  end