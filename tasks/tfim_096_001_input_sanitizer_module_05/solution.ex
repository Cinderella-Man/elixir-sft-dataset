    test "preserves href attribute on <a> tags" do
      assert Sanitizer.html(~s[<a href="https://example.com">link</a>]) ==
               ~s[<a href="https://example.com">link</a>]
    end