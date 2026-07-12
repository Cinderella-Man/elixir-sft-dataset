    test "cleans traversal and counts", %{server: s} do
      assert {:ok, "etcpasswd"} = Sanitizer.sanitize_filename(s, "../etc/passwd")
      assert {:error, :empty} = Sanitizer.sanitize_filename(s, "/\\")

      m = Sanitizer.metrics(s)
      assert m.filenames == 2
      assert m.filenames_blocked == 1
      assert m.filenames_truncated == 0
    end