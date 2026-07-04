  test "returns 400 when JSON is malformed", %{opts: opts} do
    bad_json = "this is not json {{"
    sig = sign(bad_json, @secret)

    conn = post_webhook(opts, bad_json, [{"stripe-signature", sig}])

    assert conn.status == 400
    assert json_body(conn)["error"] == "bad_payload"
  end