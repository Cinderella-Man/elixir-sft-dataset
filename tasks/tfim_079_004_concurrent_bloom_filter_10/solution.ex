  test "merge/2 raises when parameters differ" do
    f1 = ConcurrentBloomFilter.new(100, 0.01)
    f2 = ConcurrentBloomFilter.new(999, 0.05)

    assert_raise ArgumentError, fn -> ConcurrentBloomFilter.merge(f1, f2) end
  end