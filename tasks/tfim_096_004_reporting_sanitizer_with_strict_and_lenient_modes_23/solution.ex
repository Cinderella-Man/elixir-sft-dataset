  test "text escapes quotes and apostrophes without double-escaping ampersands" do
    assert {:ok, "He said &quot;hi&quot; &amp; it&#39;s fine", [:escaped_html]} =
             Sanitizer.text(~s(He said "hi" & it's fine))
  end