  test "handles CRLF line endings" do
    md = "# Root\r\n- **Item**: Desc (tag)\r\n"
    assert [%{title: "Root", items: [%{name: "Item", tags: ["tag"]}]}] = parse(md)
  end