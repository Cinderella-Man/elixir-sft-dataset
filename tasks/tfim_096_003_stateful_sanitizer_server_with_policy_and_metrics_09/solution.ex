  test "default max_filename_length truncates to 255 and counts the truncation", %{server: s} do
    long = String.duplicate("a", 300)
    assert {:ok, cleaned} = Sanitizer.sanitize_filename(s, long)
    assert cleaned == String.duplicate("a", 255)
    assert String.length(cleaned) == 255

    m = Sanitizer.metrics(s)
    assert m.filenames == 1
    assert m.filenames_truncated == 1
  end