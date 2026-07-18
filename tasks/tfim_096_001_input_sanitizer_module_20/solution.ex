    test "allows safe filenames unchanged" do
      assert {:ok, "report.pdf"} = Sanitizer.filename("report.pdf")
      assert {:ok, "my_file-2024.txt"} = Sanitizer.filename("my_file-2024.txt")
    end