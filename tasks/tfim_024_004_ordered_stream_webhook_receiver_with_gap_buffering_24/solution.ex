  test "non-string stream_id returns bad_payload", %{opts: opts, store: store} do
    payload = Jason.encode!(%{"id" => "e1", "stream_id" => 7, "sequence" => 1})
    conn = post_signed(opts, payload)

    assert conn.status == 400
    assert json_body(conn)["error"] == "bad_payload"
    assert WebhookReceiver.Store.last_sequence(store, "s1") == 0
  end