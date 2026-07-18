  test "key_level for unknown bucket returns capacity", %{sp: sp} do
    assert {:ok, 7} = SharedPoolBucket.key_level(sp, "never_seen", 7, 1.0)

    # Querying does not define the bucket: asking again with a different
    # capacity still reports a fresh, full bucket at that capacity (a bucket
    # created by the first query would have been pinned at 7 tokens).
    assert {:ok, 100} = SharedPoolBucket.key_level(sp, "never_seen", 100, 1.0)
  end