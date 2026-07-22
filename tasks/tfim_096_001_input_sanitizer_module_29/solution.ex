  test "a legitimate dotfile name loses its leading dot" do
    assert {:ok, "gitignore"} = Sanitizer.filename(".gitignore")
  end