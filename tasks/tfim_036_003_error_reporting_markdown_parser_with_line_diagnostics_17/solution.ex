  test "category title is trimmed of surrounding whitespace" do
    md = "##   Spaced Title   \n- **i**: d\n"

    %{categories: [cat], errors: errors} = parse(md)

    assert cat.category == "Spaced Title"
    assert Enum.map(cat.items, & &1.name) == ["i"]
    assert errors == []
  end