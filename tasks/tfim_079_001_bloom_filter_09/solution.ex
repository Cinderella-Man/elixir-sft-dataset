  test "merge/2 raises ArgumentError when filters have different parameters" do
    f1 = BloomFilter.new(100, 0.01)
    f2 = BloomFilter.new(999, 0.05)

    assert_raise ArgumentError, fn ->
      BloomFilter.merge(f1, f2)
    end
  end