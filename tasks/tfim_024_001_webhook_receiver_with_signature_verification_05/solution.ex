  test "returns 401 when signature is empty string", %{opts: opts} do
    payload = build_event("evt_004")

    conn = post_webhook(opts, payload, [{"stripe-signature", ""}])

    assert conn.status == 401
    assert json_body(conn)["error"] == "invalid_signature"
  end