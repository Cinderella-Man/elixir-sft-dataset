  test "label order does not create duplicate series", %{db: db} do
    :ok = ShardedTSDB.insert(db, "m", %{"a" => "1", "b" => "2"}, 100, 10)
    :ok = ShardedTSDB.insert(db, "m", %{"b" => "2", "a" => "1"}, 200, 20)

    result = ShardedTSDB.query(db, "m", %{"a" => "1", "b" => "2"}, {0, 300})
    assert length(result) == 1
    [{_labels, points}] = result
    assert points == [{100, 10}, {200, 20}]
  end