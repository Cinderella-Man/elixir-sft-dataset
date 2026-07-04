  test "start_link rejects zero or negative capacity" do
    assert_raise ArgumentError, fn -> LRUCache.start_link(capacity: 0) end
    assert_raise ArgumentError, fn -> LRUCache.start_link(capacity: -1) end
  end