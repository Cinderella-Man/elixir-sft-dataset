  test "long gap drains multiple buffered events in order", %{opts: opts, store: store} do
    assert deliver(opts, "e1", "s1", 1).status == 200
    assert deliver(opts, "e4", "s1", 4).status == 202
    assert deliver(opts, "e3", "s1", 3).status == 202
    assert deliver(opts, "e2", "s1", 2).status == 200

    assert WebhookReceiver.Store.last_sequence(store, "s1") == 4
    seqs = WebhookReceiver.Store.delivered_events(store, "s1") |> Enum.map(& &1.sequence)
    assert seqs == [1, 2, 3, 4]
  end