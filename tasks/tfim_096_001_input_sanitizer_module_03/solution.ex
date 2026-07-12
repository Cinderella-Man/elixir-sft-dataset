    test "strips disallowed tags but keeps their text" do
      # NOTE: <script> is a raw-content tag — its inner text is also discarded.
      assert Sanitizer.html("<script>alert(1)</script>") == ""
      assert Sanitizer.html("<div>hello</div>") == "hello"
      assert Sanitizer.html("<p>paragraph</p>") == "paragraph"
      assert Sanitizer.html("<span>text</span>") == "text"
    end