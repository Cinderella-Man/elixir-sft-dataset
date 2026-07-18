  test "cleanup removes expired chunks", %{db: db} do
    # retention_ms = 10_000, chunk_duration_ms = 1_000
    # Insert at t=100 → chunk_start=0, expires when now > 0 + 1000 + 10_000 = 11_000
    :ok = TSDB.insert(db, "m", %{}, 100, 1)
    # Insert at t=5000 → chunk_start=5000, expires when now > 5000 + 1000 + 10_000 = 16_000
    :ok = TSDB.insert(db, "m", %{}, 5000, 2)

    # Both chunks are still within retention before the clock moves
    assert [{_labels, [{100, 1}, {5000, 2}]}] = TSDB.query(db, "m", %{}, {0, 20_000})

    # At time 12_000, the first chunk is expired but the second is not
    Clock.set(12_000)
    send(db, :cleanup)

    result = TSDB.query(db, "m", %{}, {0, 20_000})
    [{_labels, points}] = result
    assert points == [{5000, 2}]
  end