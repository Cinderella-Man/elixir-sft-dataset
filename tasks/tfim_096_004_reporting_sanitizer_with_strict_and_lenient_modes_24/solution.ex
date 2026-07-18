  test "clean filename and text succeed identically in strict mode" do
    assert {:ok, "report.pdf", []} = Sanitizer.filename("report.pdf", mode: :strict)
    assert {:ok, "report.pdf", []} = Sanitizer.filename("report.pdf", mode: :lenient)
    assert {:ok, "hello world", []} = Sanitizer.text("hello world", mode: :strict)
    assert {:ok, "hello world", []} = Sanitizer.text("hello world", mode: :lenient)
  end