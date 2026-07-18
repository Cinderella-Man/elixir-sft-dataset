  test "Levenshtein distance is exact for equal and single-character operands" do
    # Identical (case-insensitively equal) strings are distance 0.
    assert too_similar?("a", "a", 0)
    assert too_similar?("Zx9#mQpLwT7$vBn2", "zx9#mqplwt7$vbn2", 0)

    # "abc" vs "a" is exactly two deletions: not <= 1, but <= 2.
    refute too_similar?("abc", "a", 1)
    assert too_similar?("abc", "a", 2)
  end