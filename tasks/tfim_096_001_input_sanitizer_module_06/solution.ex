    test "strips non-href attributes from <a> tags" do
      assert Sanitizer.html(~s[<a href="https://x.com" onclick="evil()">link</a>]) ==
               ~s[<a href="https://x.com">link</a>]
    end