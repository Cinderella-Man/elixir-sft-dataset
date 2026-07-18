  test "server can be registered and reached by :name option" do
    {:ok, _pid} =
      LeakyBucket.start_link(
        clock: &Clock.now/0,
        name: :leaky_bucket_named_server,
        cleanup_interval_ms: :infinity
      )

    assert {:ok, 4} = LeakyBucket.acquire(:leaky_bucket_named_server, "b", 5, 1)
    assert {:ok, 3} = LeakyBucket.acquire(:leaky_bucket_named_server, "b", 5, 1)
  end