  test "github rejects an unknown secret", %{opts: opts} do
    payload = build_event("evt_g3")
    conn =
      post_webhook(opts, "github", payload, [{"x-hub-signature-256", gh_sig(payload, "rogue")}])

    assert conn.status == 401
    assert json_body(conn)["error"] == "invalid_signature"
  end