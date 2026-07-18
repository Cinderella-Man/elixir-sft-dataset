  test "cleanup removes expired chunks", %{db: db} do
    :ok = CounterTSDB.insert(db, "reqs", %{}, 100, 1)
    :ok = CounterTSDB.insert(db, "reqs", %{}, 5000, 2)

    Clock.set(12_000)
    send(db, :cleanup)

    # A subsequent public call is processed after :cleanup (FIFO mailbox),
    # so the query observes the post-cleanup state without touching internals.
    [{_labels, points}] = CounterTSDB.query(db, "reqs", %{}, {0, 20_000})
    assert points == [{5000, 2}]
  end