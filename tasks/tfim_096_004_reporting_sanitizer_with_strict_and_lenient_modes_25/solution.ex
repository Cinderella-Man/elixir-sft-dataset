  test "filename collapses runs at the exactly-two-dot boundary only" do
    assert {:ok, "a.b", []} = Sanitizer.filename("a.b")
    assert {:ok, "a.b", [:collapsed_dots]} = Sanitizer.filename("a..b")
    assert {:ok, "a.b", [:collapsed_dots]} = Sanitizer.filename("a...b")
  end