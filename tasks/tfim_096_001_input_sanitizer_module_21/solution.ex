    test "strips null bytes" do
      assert {:ok, "file.txt"} = Sanitizer.filename("file\0.txt")
    end