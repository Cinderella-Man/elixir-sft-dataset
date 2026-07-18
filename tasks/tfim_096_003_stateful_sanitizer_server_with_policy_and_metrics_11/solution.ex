  test "script and style blocks are dropped case-insensitively across newlines", %{server: s} do
    input = "a<STYLE>\n.x { color: red; }\n</StYlE>b<ScRiPt>\nalert(1)\n</SCRIPT>c<i>d</i>"

    assert {:ok, cleaned, n} = Sanitizer.strip_html(s, input)
    assert cleaned == "abcd"
    assert n == 6

    m = Sanitizer.metrics(s)
    assert m.html_calls == 1
    assert m.tags_stripped == 6
  end