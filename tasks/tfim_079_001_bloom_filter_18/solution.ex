  test "merge/2 raises FunctionClauseError when an argument is not a filter struct" do
    f = BloomFilter.new(100, 0.01)
    look_alike = %{m: f.m, k: f.k, bits: f.bits}

    assert_raise FunctionClauseError, fn -> BloomFilter.merge(f, look_alike) end
    assert_raise FunctionClauseError, fn -> BloomFilter.merge(look_alike, f) end
    assert_raise FunctionClauseError, fn -> BloomFilter.merge(nil, f) end
    assert_raise FunctionClauseError, fn -> BloomFilter.merge(f, :not_a_filter) end
  end