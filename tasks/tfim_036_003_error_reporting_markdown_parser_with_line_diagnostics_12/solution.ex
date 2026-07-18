  test "handles CRLF line endings" do
    md = "## Category\r\n- **Item**: Desc (tag)\r\n"

    assert %{categories: [%{category: "Category", items: [%{name: "Item"}]}], errors: []} =
             parse(md)
  end