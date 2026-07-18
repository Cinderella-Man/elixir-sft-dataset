  test "malformed JSON returns bad_payload", %{opts: opts} do
    bad = "not json {{"
    conn = post_webhook(opts, bad, [{"stripe-signature", header(@now, bad, @secret)}])
    assert conn.status == 400
    assert json_body(conn)["error"] == "bad_payload"
  end