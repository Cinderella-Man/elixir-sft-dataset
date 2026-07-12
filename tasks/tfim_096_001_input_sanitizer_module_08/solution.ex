    test "rejects javascript: URLs case-insensitively" do
      assert Sanitizer.html(~s[<a href="JavaScript:alert(1)">click</a>]) == "click"
      assert Sanitizer.html(~s[<a href="JAVASCRIPT:alert(1)">click</a>]) == "click"
    end