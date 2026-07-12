    test "passes through allowed tags untouched" do
      assert Sanitizer.html("<b>bold</b>") == "<b>bold</b>"
      assert Sanitizer.html("<i>italic</i>") == "<i>italic</i>"
      assert Sanitizer.html("<em>em</em>") == "<em>em</em>"
      assert Sanitizer.html("<strong>strong</strong>") == "<strong>strong</strong>"
    end