  test "a single bucket accumulates count/sum/min/max/avg", %{db: db} do
    :ok = RollupTSDB.insert(db, "cpu", %{"host" => "a"}, 100, 10)
    :ok = RollupTSDB.insert(db, "cpu", %{"host" => "a"}, 200, 20)
    :ok = RollupTSDB.insert(db, "cpu", %{"host" => "a"}, 300, 30)

    [{%{"host" => "a"}, [{0, stats}]}] = RollupTSDB.query(db, "cpu", %{"host" => "a"}, {0, 900})

    assert stats.count == 3
    assert stats.sum == 60
    assert stats.min == 10
    assert stats.max == 30
    assert_in_delta stats.avg, 20.0, 0.0001
  end