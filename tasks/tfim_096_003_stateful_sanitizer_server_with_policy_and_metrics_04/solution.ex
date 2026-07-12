    test "truncates to max_filename_length and counts truncations" do
      {:ok, s} = Sanitizer.start_link(max_filename_length: 5)
      assert {:ok, "abcde"} = Sanitizer.sanitize_filename(s, "abcdefghij")
      assert {:ok, "xy"} = Sanitizer.sanitize_filename(s, "xy")

      m = Sanitizer.metrics(s)
      assert m.filenames == 2
      assert m.filenames_truncated == 1
    end