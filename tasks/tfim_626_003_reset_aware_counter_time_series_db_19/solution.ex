  test "cleanup drops a chunk whose end exactly equals the retention threshold", %{db: db} do
    # chunk_duration_ms 1_000, retention_ms 10_000.
    :ok = CounterTSDB.insert(db, "reqs", %{}, 100, 1)
    :ok = CounterTSDB.insert(db, "reqs", %{}, 1_000, 2)

    # now - retention_ms = 1_000. Chunk 0 ends at 0 + 1_000 == 1_000 -> removed.
    # Chunk 1_000 ends at 2_000 > 1_000 -> kept.
    Clock.set(11_000)
    send(db, :cleanup)

    [{_labels, points}] = CounterTSDB.query(db, "reqs", %{}, {0, 20_000})
    assert points == [{1_000, 2}]
  end