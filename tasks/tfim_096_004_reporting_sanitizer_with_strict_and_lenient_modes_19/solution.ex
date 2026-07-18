    test "empty text is valid (no hard failure)" do
      assert {:ok, "", []} = Sanitizer.text("")
      assert {:ok, "", [:trimmed_whitespace]} = Sanitizer.text("   ")
    end