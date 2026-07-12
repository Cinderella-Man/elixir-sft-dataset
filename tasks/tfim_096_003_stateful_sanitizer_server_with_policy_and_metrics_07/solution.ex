    test "zeroes everything", %{server: s} do
      Sanitizer.sanitize_identifier(s, "ok")
      Sanitizer.strip_html(s, "<b>x</b>")
      assert :ok = Sanitizer.reset_metrics(s)

      m = Sanitizer.metrics(s)
      assert m.identifiers == 0
      assert m.tags_stripped == 0
      assert m.html_calls == 0
    end