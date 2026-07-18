  test "Levenshtein distance is exact for multi-edit pairs" do
    # "kitten" -> "sitting" costs exactly 3 edits: not <= 2, but <= 3.
    refute too_similar?("sitting", "kitten", 2)
    assert too_similar?("sitting", "kitten", 3)

    # One extra leading character is exactly one deletion: not <= 0, but <= 1.
    refute too_similar?("xabc", "abc", 0)
    assert too_similar?("xabc", "abc", 1)
  end