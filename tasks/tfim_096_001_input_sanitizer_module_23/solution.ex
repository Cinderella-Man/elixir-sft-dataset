    test "strips backslashes (Windows traversal)" do
      {:ok, result} = Sanitizer.filename("..\\Windows\\System32")
      refute result =~ "\\"
      refute result =~ ".."
    end