  test "remove/2 makes an isolated item a non-member" do
    filter =
      CountingBloomFilter.new(100, 0.01)
      |> CountingBloomFilter.add("solo")

    assert CountingBloomFilter.member?(filter, "solo")
    filter = CountingBloomFilter.remove(filter, "solo")
    refute CountingBloomFilter.member?(filter, "solo")
  end