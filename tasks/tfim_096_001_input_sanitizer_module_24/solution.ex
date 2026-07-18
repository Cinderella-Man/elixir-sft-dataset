    test "collapses multiple consecutive dots" do
      {:ok, result} = Sanitizer.filename("file...txt")
      refute result =~ ".."
    end