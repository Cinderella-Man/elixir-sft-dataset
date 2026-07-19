# Make this test suite pass

Below is a complete, self-contained ExUnit test suite. Treat it as the
full specification: write the module (or modules) under test so that
every test passes. Use only what the tests themselves require — the
standard library and OTP unless the suite references anything else.
Follow idiomatic Elixir house style (`@moduledoc`, `@doc` + `@spec` on
the public API, no compiler warnings).

## The test suite

```elixir
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
                 items: [
                   %{name: "Hammer", description: "Drives nails", tags: ["hardware", "manual"]}
                 ]
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

    assert %{categories: [%{category: "Category", items: [%{name: "Item"}]}], errors: []} =
             parse(md)
  end

  test "suppression of a duplicate section ends at the next distinct heading" do
    md = """
    ## A
    - **x**: d
    ## A
    - **suppressed**: gone
    ## B
    - **y**: d2
    """

    %{categories: cats, errors: errors} = parse(md)

    assert cats == [
             %{category: "A", items: [%{name: "x", description: "d", tags: []}]},
             %{category: "B", items: [%{name: "y", description: "d2", tags: []}]}
           ]

    assert errors == [%{line: 3, content: "## A", reason: :duplicate_category}]
  end

  test "duplicate category is detected by trimmed title comparison" do
    md = "## A\n- **x**: d\n##   A  \n- **y**: d2\n"

    %{categories: cats, errors: errors} = parse(md)

    assert cats == [%{category: "A", items: [%{name: "x", description: "d", tags: []}]}]
    assert errors == [%{line: 3, content: "##   A", reason: :duplicate_category}]
  end

  test "error content has trailing whitespace trimmed off the original line" do
    md = "## H\n- broken bullet   \n###  Deep   \n"

    %{errors: errors} = parse(md)

    assert errors == [
             %{line: 2, content: "- broken bullet", reason: :malformed_item},
             %{line: 3, content: "###  Deep", reason: :unsupported_heading}
           ]
  end

  test "multiple categories and their items keep document order" do
    md = """
    ## First
    - **a1**: one
    - **a2**: two (t)
    ## Second
    - **b1**: three
    """

    %{categories: cats, errors: errors} = parse(md)

    assert Enum.map(cats, & &1.category) == ["First", "Second"]
    assert Enum.map(hd(cats).items, & &1.name) == ["a1", "a2"]
    assert Enum.map(List.last(cats).items, & &1.name) == ["b1"]
    assert errors == []
  end

  test "category title is trimmed of surrounding whitespace" do
    md = "##   Spaced Title   \n- **i**: d\n"

    %{categories: [cat], errors: errors} = parse(md)

    assert cat.category == "Spaced Title"
    assert Enum.map(cat.items, & &1.name) == ["i"]
    assert errors == []
  end

  test "blank lines and arbitrary prose produce no errors" do
    md = """
    ## H

    Some introductory prose.
    Another paragraph mentioning - a dash mid-sentence.

    - **i**: d (a)

    Closing prose.
    """

    %{categories: [%{items: items}], errors: errors} = parse(md)

    assert Enum.map(items, & &1.name) == ["i"]
    assert errors == []
  end
end
```

Give me the complete implementation in a single file — the module(s)
alone, not the tests.
