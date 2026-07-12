  test "query restricts buckets to those with bucket_start in range (inclusive)", %{db: db} do
    :ok = RollupTSDB.insert(db, "m", %{}, 500, 1)
    :ok = RollupTSDB.insert(db, "m", %{}, 1500, 2)
    :ok = RollupTSDB.insert(db, "m", %{}, 2500, 3)

    [{_labels, buckets}] = RollupTSDB.query(db, "m", %{}, {1000, 2000})
    assert Enum.map(buckets, &elem(&1, 0)) == [1000, 2000]
  end