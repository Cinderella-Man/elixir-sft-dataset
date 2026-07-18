    test "reports trimming and escaping in order" do
      assert {:ok, "&lt;x&gt;", [:trimmed_whitespace, :escaped_html]} =
               Sanitizer.text("  <x>  ")
    end