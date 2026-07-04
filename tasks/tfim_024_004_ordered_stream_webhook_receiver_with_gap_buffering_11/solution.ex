  test "missing sequence returns bad_payload", %{opts: opts} do
    payload = Jason.encode!(%{"id" => "e1", "stream_id" => "s1"})
    conn = post_signed(opts, payload)
    assert conn.status == 400
    assert json_body(conn)["error"] == "bad_payload"
  end