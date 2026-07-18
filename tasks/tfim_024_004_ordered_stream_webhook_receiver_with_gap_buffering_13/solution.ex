  test "malformed JSON returns bad_payload", %{opts: opts} do
    conn = post_signed(opts, "not json {{")
    assert conn.status == 400
    assert json_body(conn)["error"] == "bad_payload"
  end