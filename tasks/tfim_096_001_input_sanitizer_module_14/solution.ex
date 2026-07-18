    test "respects custom :allow option" do
      result = Sanitizer.html("<span>hello</span><b>world</b>", allow: ["span"])
      # <span> is in the allowlist so its tag is preserved; <b> is not, so only
      # its text content survives.
      assert result == "<span>hello</span>world"
      refute result =~ "<b>"
    end