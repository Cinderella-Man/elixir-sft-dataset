  test "default options start four shards", _ctx do
    {:ok, db} = ShardedTSDB.start_link([])
    assert ShardedTSDB.shard_count(db) == 4
  end