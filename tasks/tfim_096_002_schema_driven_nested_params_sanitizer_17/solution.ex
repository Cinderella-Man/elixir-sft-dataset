  test "text strips C0 controls but keeps tab, newline and carriage return" do
    raw = "  a\x01b\tc\nd\re\x0B\x0C\x1F&  "

    assert {:ok, %{"note" => cleaned}} =
             Sanitizer.sanitize(%{"note" => raw}, %{"note" => :text})

    assert cleaned == "ab\tc\nd\re&amp;"
  end