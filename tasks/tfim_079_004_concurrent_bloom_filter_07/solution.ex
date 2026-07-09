  test "false positive rate stays near the configured value" do
    n = 1_000
    p = 0.03
    filter = ConcurrentBloomFilter.new(n, p)

    Enum.each(1..n, fn i -> ConcurrentBloomFilter.add(filter, "present-#{i}") end)

    false_positives =
      Enum.count(1..n, fn i -> ConcurrentBloomFilter.member?(filter, "absent-#{i}") end)

    observed = false_positives / n

    assert observed < p * 2,
           "False positive rate #{observed} exceeded 2x target #{p}"
  end