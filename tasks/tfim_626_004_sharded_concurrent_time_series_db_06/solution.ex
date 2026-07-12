  test "query includes points exactly at both range endpoints", %{db: db} do
    for ts <- [100, 200, 300] do
      :ok = ShardedTSDB.insert(db, "m", %{}, ts, ts)
    end

    [{_labels, points}] = ShardedTSDB.query(db, "m", %{}, {100, 300})
    assert points == [{100, 100}, {200, 200}, {300, 300}]
  end