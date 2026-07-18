    test "escapes html and reports it" do
      assert {:ok, "&lt;b&gt;hi&lt;/b&gt;", [:escaped_html]} = Sanitizer.text("<b>hi</b>")
    end