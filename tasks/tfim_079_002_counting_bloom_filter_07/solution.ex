  test "remove/2 respects multiset semantics" do
    filter =
      CountingBloomFilter.new(100, 0.01)
      |> CountingBloomFilter.add("dup")
      |> CountingBloomFilter.add("dup")

    assert CountingBloomFilter.count(filter) == 2

    filter = CountingBloomFilter.remove(filter, "dup")
    assert CountingBloomFilter.member?(filter, "dup")
    assert CountingBloomFilter.count(filter) == 1

    filter = CountingBloomFilter.remove(filter, "dup")
    refute CountingBloomFilter.member?(filter, "dup")
    assert CountingBloomFilter.count(filter) == 0
  end