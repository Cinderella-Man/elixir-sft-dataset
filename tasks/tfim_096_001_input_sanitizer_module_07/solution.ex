    test "rejects javascript: URLs — strips the tag, keeps text" do
      assert Sanitizer.html(~s[<a href="javascript:alert(1)">click</a>]) == "click"
    end