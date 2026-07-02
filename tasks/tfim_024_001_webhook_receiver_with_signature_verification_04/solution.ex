  test "returns 401 when signature header is missing", %{opts: opts} do
    payload = build_event("evt_003")

    conn = post_webhook(opts, payload, [])

    assert conn.status == 401
    assert json_body(conn)["error"] == "invalid_signature"
  end