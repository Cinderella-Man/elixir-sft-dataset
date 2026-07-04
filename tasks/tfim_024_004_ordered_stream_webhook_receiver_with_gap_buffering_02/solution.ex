  test "in-order deliveries are all received", %{opts: opts, store: store} do
    for seq <- 1..3 do
      conn = deliver(opts, "e#{seq}", "s1", seq)
      assert conn.status == 200
      assert json_body(conn)["status"] == "received"
    end

    assert WebhookReceiver.Store.last_sequence(store, "s1") == 3
    seqs = WebhookReceiver.Store.delivered_events(store, "s1") |> Enum.map(& &1.sequence)
    assert seqs == [1, 2, 3]
    assert WebhookReceiver.Store.buffered_sequences(store, "s1") == []
  end