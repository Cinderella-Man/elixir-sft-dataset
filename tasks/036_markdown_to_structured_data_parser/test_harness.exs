defmodule MarkdownParserTest do
  use ExUnit.Case, async: true

  # -------------------------------------------------------
  # Helpers
  # -------------------------------------------------------

  defp parse(md), do: MarkdownParser.parse(md)

  # -------------------------------------------------------
  # Basic parsing
  # -------------------------------------------------------

  test "parses a single category with one fully-formed item" do
    md = """
    ## Tools

    - **Hammer**: Drives nails (hardware, manual)
    """

    assert parse(md) == [
             %{
               category: "Tools",
               items: [
                 %{name: "Hammer", description: "Drives nails", tags: ["hardware", "manual"]}
               ]
             }
           ]
  end

  test "parses multiple categories in document order" do
    md = """
    ## Fruits

    - **Apple**: A red fruit (sweet, crunchy)

    ## Vegetables

    - **Carrot**: An orange vegetable (savory, crunchy)
    """

    result = parse(md)
    assert length(result) == 2
    assert Enum.at(result, 0).category == "Fruits"
    assert Enum.at(result, 1).category == "Vegetables"
  end

  test "parses multiple items under one category" do
    md = """
    ## Languages

    - **Elixir**: Functional language (fp, concurrent)
    - **Rust**: Systems language (systems, safe)
    - **Python**: Scripting language (scripting, dynamic)
    """

    %{category: "Languages", items: items} = parse(md) |> hd()
    assert length(items) == 3
    assert Enum.map(items, & &1.name) == ["Elixir", "Rust", "Python"]
  end

  # -------------------------------------------------------
  # Items without tags
  # -------------------------------------------------------

  test "item with no parentheses gets empty tags list" do
    md = """
    ## Things

    - **Widget**: A small gadget
    """

    [%{items: [item]}] = parse(md)
    assert item.name == "Widget"
    assert item.description == "A small gadget"
    assert item.tags == []
  end

  test "mix of tagged and untagged items in same category" do
    md = """
    ## Mix

    - **A**: Has tags (x, y)
    - **B**: No tags
    """

    [%{items: [a, b]}] = parse(md)
    assert a.tags == ["x", "y"]
    assert b.tags == []
  end

  # -------------------------------------------------------
  # Tag whitespace handling
  # -------------------------------------------------------

  test "tags are individually trimmed of whitespace" do
    md = """
    ## Misc

    - **Item**: Desc ( alpha ,  beta , gamma )
    """

    [%{items: [item]}] = parse(md)
    assert item.tags == ["alpha", "beta", "gamma"]
  end

  # -------------------------------------------------------
  # Edge cases — empty / missing content
  # -------------------------------------------------------

  test "empty string returns empty list" do
    assert parse("") == []
  end

  test "document with only non-H2 headings returns empty list" do
    md = """
    # Top level
    ### Too deep
    #### Also too deep
    """

    assert parse(md) == []
  end

  test "H2 heading with no items has empty items list" do
    md = """
    ## EmptyCategory
    """

    assert parse(md) == [%{category: "EmptyCategory", items: []}]
  end

  test "multiple empty categories" do
    md = """
    ## First

    ## Second

    ## Third
    """

    result = parse(md)
    assert length(result) == 3
    assert Enum.all?(result, fn %{items: items} -> items == [] end)
    assert Enum.map(result, & &1.category) == ["First", "Second", "Third"]
  end

  # -------------------------------------------------------
  # Lines before any heading are discarded
  # -------------------------------------------------------

  test "bullet items before first H2 heading are discarded" do
    md = """
    - **Orphan**: Should be ignored (lost)

    ## Real

    - **Valid**: Kept (yes)
    """

    result = parse(md)
    assert length(result) == 1
    assert hd(result).category == "Real"
    assert length(hd(result).items) == 1
  end

  # -------------------------------------------------------
  # Non-H2 headings are ignored
  # -------------------------------------------------------

  test "H1 headings are ignored and do not create categories" do
    md = """
    # Document Title

    ## Actual Category

    - **Thing**: A thing (a, b)
    """

    result = parse(md)
    assert length(result) == 1
    assert hd(result).category == "Actual Category"
  end

  test "H3 and deeper headings are ignored mid-document" do
    md = """
    ## Real

    - **Item**: Desc (t)

    ### Not a category

    - **Also**: Under real still? (maybe)
    """

    # H3 is ignored, so "Also" bullet may either be attributed to "Real"
    # or dropped — either way, "Not a category" must NOT appear as a category.
    result = parse(md)
    category_names = Enum.map(result, & &1.category)
    refute "Not a category" in category_names
  end

  # -------------------------------------------------------
  # Nested / malformed bullets are ignored
  # -------------------------------------------------------

  test "nested bullet lines (indented with spaces) are ignored" do
    md = """
    ## Nested

    - **Parent**: Top level item (a)
      - **Child**: Should be ignored (b)
    """

    [%{items: items}] = parse(md)
    assert length(items) == 1
    assert hd(items).name == "Parent"
  end

  test "bullet lines not matching the bold-name format are ignored" do
    md = """
    ## Misc

    - just a plain bullet
    - **Good**: Proper item (tag)
    - another bad bullet (fake, tags)
    """

    [%{items: items}] = parse(md)
    assert length(items) == 1
    assert hd(items).name == "Good"
  end

  # -------------------------------------------------------
  # Whitespace robustness
  # -------------------------------------------------------

  test "category name is trimmed of surrounding whitespace" do
    md = "##   Spaced Out   \n- **Item**: Desc (t)\n"
    [%{category: cat}] = parse(md)
    assert cat == "Spaced Out"
  end

  test "handles CRLF line endings" do
    md = "## Category\r\n- **Item**: Desc (tag)\r\n"
    assert [%{category: "Category", items: [%{name: "Item"}]}] = parse(md)
  end
end
