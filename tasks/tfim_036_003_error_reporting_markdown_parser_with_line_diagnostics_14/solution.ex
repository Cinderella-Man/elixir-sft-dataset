  test "duplicate category is detected by trimmed title comparison" do
    md = "## A\n- **x**: d\n##   A  \n- **y**: d2\n"

    %{categories: cats, errors: errors} = parse(md)

    assert cats == [%{category: "A", items: [%{name: "x", description: "d", tags: []}]}]
    assert errors == [%{line: 3, content: "##   A", reason: :duplicate_category}]
  end