    test "rejects javascript: URLs with leading whitespace" do
      assert Sanitizer.html(~s[<a href="  javascript:alert(1)">click</a>]) == "click"
    end