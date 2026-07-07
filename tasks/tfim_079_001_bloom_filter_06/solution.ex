  test "false positive rate stays near the configured value" do
    n = 1_000
    p = 0.03
    filter = BloomFilter.new(n, p)

    # Add n distinct items
    filter =
      Enum.reduce(1..n, filter, fn i, f ->
        BloomFilter.add(f, "present-#{i}")
      end)

    # Test n absent items and count false positives
    false_positives =
      Enum.count(1..n, fn i ->
        BloomFilter.member?(filter, "absent-#{i}")
      end)

    observed_rate = false_positives / n

    # Allow 2× headroom around the configured rate
    assert observed_rate < p * 2,
           "False positive rate #{observed_rate} exceeded 2× target #{p}"
  end