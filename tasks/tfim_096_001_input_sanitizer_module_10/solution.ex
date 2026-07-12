    test "strips nested disallowed tags, preserving text" do
      assert Sanitizer.html("<div><b>bold</b> and plain</div>") == "<b>bold</b> and plain"
    end