    test "metrics stay exact under many concurrent callers", %{server: s} do
      valid =
        for _ <- 1..100 do
          Task.async(fn -> Sanitizer.sanitize_identifier(s, "users") end)
        end

      invalid =
        for _ <- 1..50 do
          Task.async(fn -> Sanitizer.sanitize_identifier(s, "###") end)
        end

      files =
        for _ <- 1..40 do
          Task.async(fn -> Sanitizer.sanitize_filename(s, "../a/b") end)
        end

      Enum.each(valid ++ invalid ++ files, &Task.await/1)

      m = Sanitizer.metrics(s)
      assert m.identifiers == 150
      assert m.identifiers_blocked == 50
      assert m.filenames == 40
      assert m.filenames_blocked == 0
    end