  test "heading titles are trimmed of surrounding whitespace" do
    md = "#    Spaced Title   \n"

    assert [%{title: "Spaced Title", level: 1, items: [], children: []}] = parse(md)
  end