  test "compound false positive rate stays bounded as the filter scales" do
    initial = 100
    p = 0.02
    filter = ScalableBloomFilter.new(initial, p)

    # Insert well beyond the initial capacity to force several slices.
    n = 300
    filter =
      Enum.reduce(1..n, filter, fn i, f ->
        ScalableBloomFilter.add(f, "present-#{i}")
      end)

    assert ScalableBloomFilter.num_slices(filter) > 1

    trials = 1_000
    false_positives =
      Enum.count(1..trials, fn i ->
        ScalableBloomFilter.member?(filter, "absent-#{i}")
      end)

    observed = false_positives / trials
    assert observed < p * 3,
           "compound false positive rate #{observed} exceeded bound #{p * 3}"
  end