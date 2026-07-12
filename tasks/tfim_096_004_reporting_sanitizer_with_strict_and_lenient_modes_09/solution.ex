    test "reports null bytes" do
      assert {:ok, "file.txt", [:removed_null_bytes]} = Sanitizer.filename("file\0.txt")
    end