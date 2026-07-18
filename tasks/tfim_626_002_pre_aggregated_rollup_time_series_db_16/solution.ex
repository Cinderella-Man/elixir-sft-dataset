  test "points exactly on a bucket boundary go into the correct bucket", %{db: db} do
    :ok = RollupTSDB.insert(db, "m", %{}, 999, 1)
    :ok = RollupTSDB.insert(db, "m", %{}, 1000, 2)
    :ok = RollupTSDB.insert(db, "m", %{}, 1001, 3)

    [{_labels, buckets}] = RollupTSDB.query(db, "m", %{}, {0, 2000})
    starts = Enum.map(buckets, &elem(&1, 0))
    assert starts == [0, 1000]

    {1000, b1} = Enum.find(buckets, fn {bs, _} -> bs == 1000 end)
    assert b1.count == 2
    assert b1.sum == 5
  end