  test "coordinator can be registered under a name", _ctx do
    {:ok, _pid} = ShardedTSDB.start_link(name: :named_tsdb, shards: 3)
    assert ShardedTSDB.shard_count(:named_tsdb) == 3
    assert :ok = ShardedTSDB.insert(:named_tsdb, "m", %{}, 100, 1)
    assert [{_, [{100, 1}]}] = ShardedTSDB.query(:named_tsdb, "m", %{}, {0, 200})
  end