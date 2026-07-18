  test "shard_of is independent of label map ordering", %{db: db} do
    a = ShardedTSDB.shard_of(db, "m", %{"a" => "1", "b" => "2"})
    b = ShardedTSDB.shard_of(db, "m", %{"b" => "2", "a" => "1"})
    assert a == b
  end