  test "merge/2 error message names both filters' m and k values" do
    f1 = BloomFilter.new(100, 0.01)
    f2 = BloomFilter.new(999, 0.05)

    error = assert_raise ArgumentError, fn -> BloomFilter.merge(f1, f2) end

    assert error.message =~ "cannot merge filters with different parameters"
    assert error.message =~ "filter1 has m=#{f1.m}, k=#{f1.k}"
    assert error.message =~ "filter2 has m=#{f2.m}, k=#{f2.k}"
  end