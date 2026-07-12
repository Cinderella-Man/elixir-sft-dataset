    test "removes script content and counts tags", %{server: s} do
      assert {:ok, "Hello world", n} =
               Sanitizer.strip_html(s, "<b>Hello</b> <script>alert(1)</script>world")

      # <b>, </b>, <script>, </script> = 4 tag tokens in the original
      assert n == 4

      assert {:ok, "plain", _} = Sanitizer.strip_html(s, "<div><p>plain</p></div>")

      m = Sanitizer.metrics(s)
      assert m.html_calls == 2
      assert m.tags_stripped == 4 + 4
    end