    test "strips all attributes from allowed tags (except href on <a>)" do
      assert Sanitizer.html(~s[<b class="evil">text</b>]) == "<b>text</b>"
      assert Sanitizer.html(~s[<i style="color:red">text</i>]) == "<i>text</i>"
    end