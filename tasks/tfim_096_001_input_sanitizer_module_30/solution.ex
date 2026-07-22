  test "consecutive dots collapse to exactly one dot, positively" do
    assert {:ok, "file.txt"} = Sanitizer.filename("file...txt")
  end