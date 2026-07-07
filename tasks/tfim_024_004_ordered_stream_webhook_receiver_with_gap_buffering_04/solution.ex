  test "future event buffered (202) then drained when gap fills", %{opts: opts, store: store} do
    assert json_body(deliver(opts, "e1", "s1", 1))["status"] == "received"

    conn3 = deliver(opts, "e3", "s1", 3)
    assert conn3.status == 202
    assert json_body(conn3)["status"] == "buffered"
    assert WebhookReceiver.Store.last_sequence(store, "s1") == 1
    assert WebhookReceiver.Store.buffered_sequences(store, "s1") == [3]

    conn2 = deliver(opts, "e2", "s1", 2)
    assert conn2.status == 200
    assert json_body(conn2)["status"] == "received"

    assert WebhookReceiver.Store.last_sequence(store, "s1") == 3
    assert WebhookReceiver.Store.buffered_sequences(store, "s1") == []
    seqs = WebhookReceiver.Store.delivered_events(store, "s1") |> Enum.map(& &1.sequence)
    assert seqs == [1, 2, 3]
  end