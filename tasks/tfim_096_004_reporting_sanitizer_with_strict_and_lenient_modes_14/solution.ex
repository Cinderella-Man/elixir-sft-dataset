    test "clean text has no violations" do
      assert {:ok, "hello world", []} = Sanitizer.text("hello world")
    end