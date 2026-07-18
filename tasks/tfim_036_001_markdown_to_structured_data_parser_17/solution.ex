  test "category name is trimmed of surrounding whitespace" do
    md = "##   Spaced Out   \n- **Item**: Desc (t)\n"
    [%{category: cat}] = parse(md)
    assert cat == "Spaced Out"
  end