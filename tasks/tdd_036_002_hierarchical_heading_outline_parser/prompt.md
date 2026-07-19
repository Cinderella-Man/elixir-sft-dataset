# Make this test suite pass

Below is a complete, self-contained ExUnit test suite. Treat it as the
full specification: write the module (or modules) under test so that
every test passes. Use only what the tests themselves require — the
standard library and OTP unless the suite references anything else.
Follow idiomatic Elixir house style (`@moduledoc`, `@doc` + `@spec` on
the public API, no compiler warnings).

## The test suite

```elixir
defmodule MarkdownOutlineTest do
  use ExUnit.Case, async: false

  defp parse(md), do: MarkdownOutline.parse(md)

  test "single top-level heading with one item and no children" do
    md = """
    # Root
    - **x**: desc (a)
    """

    assert parse(md) == [
             %{
               title: "Root",
               level: 1,
               items: [%{name: "x", description: "desc", tags: ["a"]}],
               children: []
             }
           ]
  end

  test "deeper heading becomes a child of the shallower heading" do
    md = """
    # Parent
    - **p**: pd (a, b)
    ## Child
    - **c**: cd
    """

    assert parse(md) == [
             %{
               title: "Parent",
               level: 1,
               items: [%{name: "p", description: "pd", tags: ["a", "b"]}],
               children: [
                 %{
                   title: "Child",
                   level: 2,
                   items: [%{name: "c", description: "cd", tags: []}],
                   children: []
                 }
               ]
             }
           ]
  end

  test "same-level headings become siblings" do
    md = """
    # A
    # B
    """

    result = parse(md)
    assert length(result) == 2
    assert Enum.map(result, & &1.title) == ["A", "B"]
    assert Enum.all?(result, &(&1.children == []))
  end

  test "relative nesting: H1 then H3 makes H3 a child of H1" do
    md = """
    # Top
    ### Deep
    - **d**: under deep
    """

    [top] = parse(md)
    assert top.title == "Top"
    assert top.level == 1
    assert [deep] = top.children
    assert deep.title == "Deep"
    assert deep.level == 3
    assert [%{name: "d"}] = deep.items
  end

  test "closing a branch and opening an ancestor sibling" do
    md = """
    # One
    ## OneA
    # Two
    """

    result = parse(md)
    assert Enum.map(result, & &1.title) == ["One", "Two"]
    [one, two] = result
    assert Enum.map(one.children, & &1.title) == ["OneA"]
    assert two.children == []
  end

  test "three levels deep nesting" do
    md = """
    # L1
    ## L2
    ### L3
    - **leaf**: bottom (t)
    """

    [l1] = parse(md)
    [l2] = l1.children
    [l3] = l2.children
    assert {l1.level, l2.level, l3.level} == {1, 2, 3}
    assert [%{name: "leaf", tags: ["t"]}] = l3.items
  end

  test "items before the first heading are discarded" do
    md = """
    - **orphan**: lost (x)
    # Real
    - **kept**: yes
    """

    [node] = parse(md)
    assert node.title == "Real"
    assert Enum.map(node.items, & &1.name) == ["kept"]
  end

  test "tags are individually trimmed and empty tags dropped" do
    md = """
    # H
    - **i**: d ( a , b ,, c )
    """

    [%{items: [item]}] = parse(md)
    assert item.tags == ["a", "b", "c"]
  end

  test "nested (space-indented) bullets and malformed bullets are ignored" do
    md = """
    # H
    - **Parent**: top (a)
      - **Child**: indented ignored (b)
    - just a plain bullet
    """

    [%{items: items}] = parse(md)
    assert length(items) == 1
    assert hd(items).name == "Parent"
  end

  test "headings with seven or more hashes are ignored" do
    md = """
    # Real
    ####### Not a heading
    - **x**: kept
    """

    [node] = parse(md)
    assert node.title == "Real"
    assert Enum.map(node.items, & &1.name) == ["x"]
  end

  test "empty string returns empty list" do
    assert parse("") == []
  end

  test "handles CRLF line endings" do
    md = "# Root\r\n- **Item**: Desc (tag)\r\n"
    assert [%{title: "Root", items: [%{name: "Item", tags: ["tag"]}]}] = parse(md)
  end

  test "heading titles are trimmed of surrounding whitespace" do
    md = "#    Spaced Title   \n"

    assert [%{title: "Spaced Title", level: 1, items: [], children: []}] = parse(md)
  end

  test "multiple items and multiple children keep document order" do
    md = """
    # Root
    - **i1**: one
    - **i2**: two
    - **i3**: three
    ## C1
    ## C2
    ## C3
    """

    [root] = parse(md)
    assert Enum.map(root.items, & &1.name) == ["i1", "i2", "i3"]
    assert Enum.map(root.children, & &1.title) == ["C1", "C2", "C3"]
  end

  test "empty heading between populated siblings has empty items and children" do
    md = """
    # A
    - **a**: da
    # Empty
    # B
    - **b**: db
    """

    assert [_a, empty, _b] = parse(md)
    assert empty == %{title: "Empty", level: 1, items: [], children: []}
  end

  test "shallower heading closes deep branch and becomes an ancestor's child sibling" do
    md = """
    # One
    ## Two
    ### Three
    ## Four
    - **f**: under four
    """

    [one] = parse(md)
    assert Enum.map(one.children, & &1.title) == ["Two", "Four"]
    [two, four] = one.children
    assert Enum.map(two.children, & &1.title) == ["Three"]
    assert [%{name: "f", description: "under four", tags: []}] = four.items
    assert four.level == 2
  end

  test "six-hash heading is recognised as a level six node" do
    md = """
    # L1
    ###### L6
    - **x**: deep
    """

    [l1] = parse(md)
    assert [%{title: "L6", level: 6, items: [%{name: "x"}], children: []}] = l1.children
  end

  test "hash line without whitespace before the text is not a heading" do
    md = """
    # Real
    #NotAHeading
    - **x**: kept
    """

    [node] = parse(md)
    assert node.title == "Real"
    assert node.children == []
    assert Enum.map(node.items, & &1.name) == ["x"]
  end
end
```

Give me the complete implementation in a single file — the module(s)
alone, not the tests.
