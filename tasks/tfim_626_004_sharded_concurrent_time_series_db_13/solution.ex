  test "shard_count returns the configured number of shards", %{db: db} do
    assert ShardedTSDB.shard_count(db) == 4
  end