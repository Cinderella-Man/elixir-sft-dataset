    test "handles plain text with no tags" do
      assert Sanitizer.html("hello world") == "hello world"
    end