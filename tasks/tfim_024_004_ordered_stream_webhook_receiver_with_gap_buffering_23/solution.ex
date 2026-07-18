  test "missing id and non-string id both return bad_payload", %{opts: opts, store: store} do
    missing = Jason.encode!(%{"stream_id" => "s1", "sequence" => 1})
    conn = post_signed(opts, missing)
    assert conn.status == 400
    assert json_body(conn)["error"] == "bad_payload"

    wrong = Jason.encode!(%{"id" => 42, "stream_id" => "s1", "sequence" => 1})
    conn = post_signed(opts, wrong)
    assert conn.status == 400
    assert json_body(conn)["error"] == "bad_payload"

    assert WebhookReceiver.Store.last_sequence(store, "s1") == 0
    assert WebhookReceiver.Store.delivered_events(store, "s1") == []
  end