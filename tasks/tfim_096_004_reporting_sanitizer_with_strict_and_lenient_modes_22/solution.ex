  test "text reports control chars, trimming and escaping in fixed order" do
    assert {:ok, "&lt;a&gt;&amp;", [:removed_control_chars, :trimmed_whitespace, :escaped_html]} =
             Sanitizer.text("  \x01<a>&  ")
  end