  test "name option registers the process under the given name" do
    {:ok, _pid} =
      SharedPoolBucket.start_link(
        name: :spb_named,
        global_capacity: 10,
        global_refill_rate: 1.0,
        clock: &Clock.now/0,
        cleanup_interval_ms: :infinity
      )

    assert {:ok, 4, 9} = SharedPoolBucket.acquire(:spb_named, "alice", 5, 0.5)
    assert {:ok, 9} = SharedPoolBucket.global_level(:spb_named)
  end