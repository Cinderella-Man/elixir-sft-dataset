  test "removing an item does not evict others sharing the set" do
    filter =
      CountingBloomFilter.new(200, 0.01)
      |> CountingBloomFilter.add("keep-a")
      |> CountingBloomFilter.add("keep-b")
      |> CountingBloomFilter.add("gone")

    filter = CountingBloomFilter.remove(filter, "gone")

    assert CountingBloomFilter.member?(filter, "keep-a")
    assert CountingBloomFilter.member?(filter, "keep-b")
  end