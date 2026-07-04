defmodule MarkdownReportTest do
  use ExUnit.Case, async: false

  defp parse(md), do: MarkdownReport.parse(md)

  test "clean document has no errors" do
    md = """
    ## Tools

    - **Hammer**: Drives nails (hardware, manual)
    """

    assert parse(md) == %{
             categories: [
               %{
                 category: "Tools",
                 items: [%{name: "Hammer", description: "Drives nails", tags: ["hardware", "manual"]}]
               }
             ],
             errors: []
           }
  end

  test "malformed bullet reports line number and reason" do
    md = """
    ## Misc
    - just a plain bullet
    - **Good**: Proper (tag)
    """

    %{categories: [%{items: items}], errors: errors} = parse(md)
    assert Enum.map(items, & &1.name) == ["Good"]
    assert errors == [%{line: 2, content: "- just a plain bullet", reason: :malformed_item}]
  end

  test "orphan item before any heading is reported and discarded" do
    md = """
    - **Orphan**: lost (x)
    ## Real
    - **Kept**: yes
    """

    %{categories: [cat], errors: errors} = parse(md)
    assert cat.category == "Real"
    assert Enum.map(cat.items, & &1.name) == ["Kept"]
    assert errors == [%{line: 1, content: "- **Orphan**: lost (x)", reason: :orphan_item}]
  end

  test "unsupported headings are reported but do not close the open category" do
    md = """
    # Title
    ## Real
    ### Subsection
    - **x**: still under Real (a)
    """

    %{categories: [cat], errors: errors} = parse(md)
    assert cat.category == "Real"
    assert Enum.map(cat.items, & &1.name) == ["x"]

    reasons = Enum.map(errors, &{&1.line, &1.reason})
    assert reasons == [{1, :unsupported_heading}, {3, :unsupported_heading}]
  end

  test "duplicate category is reported and its section suppressed silently" do
    md = """
    ## A
    - **x**: d
    ## A
    - **y**: d2
    """

    %{categories: cats, errors: errors} = parse(md)
    assert cats == [%{category: "A", items: [%{name: "x", description: "d", tags: []}]}]
    assert errors == [%{line: 3, content: "## A", reason: :duplicate_category}]
  end

  test "space-indented nested bullets are silently ignored, not reported" do
    md = """
    ## H
    - **Parent**: top (a)
      - **Child**: indented (b)
    """

    %{categories: [%{items: items}], errors: errors} = parse(md)
    assert Enum.map(items, & &1.name) == ["Parent"]
    assert errors == []
  end

  test "tags are trimmed and empty tags dropped" do
    md = """
    ## H
    - **i**: d ( a , b ,, c )
    """

    %{categories: [%{items: [item]}]} = parse(md)
    assert item.tags == ["a", "b", "c"]
  end

  test "untagged item gets empty tags list" do
    md = """
    ## H
    - **Widget**: A gadget
    """

    %{categories: [%{items: [item]}]} = parse(md)
    assert item.tags == []
  end

  test "empty string returns empty categories and errors" do
    assert parse("") == %{categories: [], errors: []}
  end

  test "errors are returned in ascending line order across mixed problems" do
    md = """
    - **early**: orphan (o)
    ## Cat
    - broken bullet
    ### deep
    """

    %{errors: errors} = parse(md)
    assert Enum.map(errors, & &1.line) == [1, 3, 4]

    assert Enum.map(errors, & &1.reason) == [
             :orphan_item,
             :malformed_item,
             :unsupported_heading
           ]
  end

  test "handles CRLF line endings" do
    md = "## Category\r\n- **Item**: Desc (tag)\r\n"
    assert %{categories: [%{category: "Category", items: [%{name: "Item"}]}], errors: []} = parse(md)
  end
end