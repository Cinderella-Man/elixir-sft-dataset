  test "label order does not create duplicate series", %{db: db} do
    :ok = RollupTSDB.insert(db, "m", %{"a" => "1", "b" => "2"}, 100, 10)
    :ok = RollupTSDB.insert(db, "m", %{"b" => "2", "a" => "1"}, 200, 20)

    result = RollupTSDB.query(db, "m", %{"a" => "1", "b" => "2"}, {0, 900})
    assert length(result) == 1
    [{_labels, [{0, stats}]}] = result
    assert stats.count == 2
    assert stats.sum == 30
  end