  test "cleanup removes expired buckets but keeps fresh ones", %{db: db} do
    # retention_ms = 10_000, bucket_duration_ms = 1_000
    # bucket 0 expires when 0 + 1000 <= now - 10_000  -> now >= 11_000
    :ok = RollupTSDB.insert(db, "m", %{}, 100, 1)
    # bucket 5000 expires when 5000 + 1000 <= now - 10_000 -> now >= 16_000
    :ok = RollupTSDB.insert(db, "m", %{}, 5000, 2)

    Clock.set(12_000)
    :ok = sync_cleanup(db)

    [{_labels, buckets}] = RollupTSDB.query(db, "m", %{}, {0, 20_000})
    assert Enum.map(buckets, &elem(&1, 0)) == [5000]
  end