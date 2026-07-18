  test "a bucket is dropped exactly when start + duration equals now - retention", %{db: db} do
    # bucket 0 expires at now == 11_000; bucket 1000 expires at now == 12_000
    :ok = RollupTSDB.insert(db, "m", %{}, 100, 1)
    :ok = RollupTSDB.insert(db, "m", %{}, 1500, 2)

    Clock.set(10_999)
    :ok = sync_cleanup(db)
    [{_labels, buckets}] = RollupTSDB.query(db, "m", %{}, {0, 20_000})
    assert Enum.map(buckets, &elem(&1, 0)) == [0, 1000]

    Clock.set(11_000)
    :ok = sync_cleanup(db)
    [{_labels, kept}] = RollupTSDB.query(db, "m", %{}, {0, 20_000})
    assert Enum.map(kept, &elem(&1, 0)) == [1000]
  end