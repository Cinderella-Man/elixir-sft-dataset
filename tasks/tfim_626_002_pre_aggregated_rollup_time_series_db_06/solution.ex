  test "points fall into separate buckets by bucket_start", %{db: db} do
    # bucket_duration_ms = 1_000, boundaries at 0, 1000, 2000 ...
    :ok = RollupTSDB.insert(db, "m", %{}, 100, 1)
    :ok = RollupTSDB.insert(db, "m", %{}, 1100, 2)
    :ok = RollupTSDB.insert(db, "m", %{}, 1900, 8)

    [{_labels, buckets}] = RollupTSDB.query(db, "m", %{}, {0, 2000})
    starts = Enum.map(buckets, &elem(&1, 0))
    assert starts == [0, 1000]

    [{0, b0}, {1000, b1}] = buckets
    assert b0.sum == 1
    assert b1.sum == 10
    assert b1.count == 2
  end