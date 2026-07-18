  test "handles CRLF line endings" do
    md = "## Category\r\n- **Item**: Desc (tag)\r\n"
    assert [%{category: "Category", items: [%{name: "Item"}]}] = parse(md)
  end