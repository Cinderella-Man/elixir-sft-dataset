  test "filename of exactly max_filename_length is kept whole and not counted truncated" do
    {:ok, s} = Sanitizer.start_link(max_filename_length: 5)
    assert {:ok, "abcde"} = Sanitizer.sanitize_filename(s, "abcde")

    m = Sanitizer.metrics(s)
    assert m.filenames == 1
    assert m.filenames_truncated == 0
  end