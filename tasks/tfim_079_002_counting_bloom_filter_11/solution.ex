  test "count/1 tracks live inserts and deletes" do
    filter = CountingBloomFilter.new(100, 0.01)
    assert CountingBloomFilter.count(filter) == 0

    filter =
      Enum.reduce(1..10, filter, fn i, f -> CountingBloomFilter.add(f, "n-#{i}") end)

    assert CountingBloomFilter.count(filter) == 10

    filter = CountingBloomFilter.remove(filter, "n-1")
    assert CountingBloomFilter.count(filter) == 9
  end