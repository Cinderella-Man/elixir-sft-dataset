  test "text keeps tab, newline and carriage return untouched" do
    assert {:ok, "a\tb\nc\rd", []} = Sanitizer.text("a\tb\nc\rd")
    assert {:ok, "a\tb\nc\rd", []} = Sanitizer.text("a\tb\nc\rd", mode: :strict)
  end