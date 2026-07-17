# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule MarkdownParser do
  @moduledoc """
  Parses a subset of Markdown into structured category/item data.

  ## Document conventions

  * `## Heading` lines define category names (H2 only).
  * Bullet items beneath a heading follow the format:
    `- **Item Name**: description (tag1, tag2)`
  * Tags are optional; an item with no parentheses receives `tags: []`.
  * All other lines (blank lines, non-matching bullets, H1/H3+ headings,
    nested list items starting with more than one `-`) are silently ignored.
  * Bullet items that appear before the first `## heading` are discarded.
  """

  # ---------------------------------------------------------------------------
  # Compiled regexes (module-level constants)
  # ---------------------------------------------------------------------------

  # Matches exactly an H2 heading: "## Some Title"
  # Captures the trimmed heading text.
  @heading_re ~r/^##\s+(.+)$/

  # Matches a top-level bullet item that starts with exactly one "-" (not "  -",
  # not "--", etc.) and contains a bold name followed by a colon.
  # Group 1 – item name (inside **…**)
  # Group 2 – description (everything after ": " up to an optional trailing tag list)
  # Group 3 – raw tag string inside the final "(…)" if present
  @item_re ~r/^-\s+\*\*(.+?)\*\*:\s+(.*?)(?:\s+\(([^)]*)\))?\s*$/

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Parses `markdown` and returns a list of category maps in document order.

  ## Return shape

      [
        %{
          category: "Category Name",
          items: [
            %{name: "Item Name", description: "some description", tags: ["tag1", "tag2"]}
          ]
        }
      ]

  Returns `[]` for an empty string or a document with no H2 headings.
  """
  @spec parse(binary()) :: [%{category: String.t(), items: list(map())}]
  def parse(markdown) when is_binary(markdown) do
    markdown
    |> split_lines()
    |> classify_lines()
    |> build_categories()
  end

  # ---------------------------------------------------------------------------
  # Step 1 – split into trimmed lines, drop truly empty ones early
  # ---------------------------------------------------------------------------

  defp split_lines(markdown) do
    markdown
    |> String.split("\n")
    |> Enum.map(&String.trim_trailing/1)
  end

  # ---------------------------------------------------------------------------
  # Step 2 – classify each line as {:heading, name} | {:item, map} | :ignore
  # ---------------------------------------------------------------------------

  defp classify_lines(lines) do
    Enum.map(lines, &classify_line/1)
  end

  defp classify_line(line) do
    cond do
      match_heading(line) -> match_heading(line)
      match_item(line) -> match_item(line)
      true -> :ignore
    end
  end

  defp match_heading(line) do
    case Regex.run(@heading_re, line, capture: :all_but_first) do
      [name] -> {:heading, String.trim(name)}
      _ -> nil
    end
  end

  defp match_item(line) do
    case Regex.run(@item_re, line, capture: :all_but_first) do
      [name, description] ->
        {:item, build_item(name, description, nil)}

      [name, description, raw_tags] ->
        {:item, build_item(name, description, raw_tags)}

      _ ->
        nil
    end
  end

  defp build_item(name, description, raw_tags) do
    tags =
      case raw_tags do
        nil ->
          []

        "" ->
          []

        str ->
          str
          |> String.split(",")
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))
      end

    %{name: String.trim(name), description: String.trim(description), tags: tags}
  end

  # ---------------------------------------------------------------------------
  # Step 3 – fold classified lines into a list of category maps
  # ---------------------------------------------------------------------------
  #
  # State:
  #   categories  – accumulated result list (reversed; reversed again at the end)
  #   current     – the category map being built, or nil if no heading seen yet
  #

  defp build_categories(classified_lines) do
    initial = %{categories: [], current: nil}

    %{categories: cats, current: last} =
      Enum.reduce(classified_lines, initial, &process_line/2)

    # Flush the final in-progress category (if any).
    cats =
      if last do
        [finalise(last) | cats]
      else
        cats
      end

    Enum.reverse(cats)
  end

  # A new H2 heading: flush current category (if any), open a new one.
  defp process_line({:heading, name}, %{categories: cats, current: current}) do
    cats =
      if current do
        [finalise(current) | cats]
      else
        cats
      end

    %{categories: cats, current: %{category: name, items: []}}
  end

  # A valid bullet item: append to the current category (discard if no heading yet).
  defp process_line({:item, item}, %{categories: cats, current: current}) do
    if current do
      %{categories: cats, current: Map.update!(current, :items, &[item | &1])}
    else
      %{categories: cats, current: nil}
    end
  end

  # Anything else: skip.
  defp process_line(:ignore, state), do: state

  # Reverse the items list (they were prepended for efficiency).
  defp finalise(%{category: name, items: items}) do
    %{category: name, items: Enum.reverse(items)}
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
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
    # TODO
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

  test "category whose only bullets are malformed still appears with empty items" do
    md = """
    ## Empty By Malformation

    - plain bullet with no bold name
      - **Nested**: indented child (x)
    - another bad bullet (fake, tags)

    ## Next

    - **Real**: Kept (t)
    """

    result = parse(md)
    assert Enum.map(result, & &1.category) == ["Empty By Malformation", "Next"]
    assert Enum.at(result, 0).items == []
    assert Enum.at(result, 1).items == [%{name: "Real", description: "Kept", tags: ["t"]}]
  end

  test "bullets following ignored H3 and H1 headings stay in the preceding H2 category" do
    md = """
    ## Real

    - **First**: Before the H3 (a)

    ### Not a category

    - **Second**: After the H3 (b)

    # Also not a category

    - **Third**: After the H1 (c)
    """

    assert [%{category: "Real", items: items}] = parse(md)
    assert Enum.map(items, & &1.name) == ["First", "Second", "Third"]
    assert Enum.map(items, & &1.tags) == [["a"], ["b"], ["c"]]
  end

  test "bullet lines starting with more than one dash are ignored" do
    md = """
    ## Dashes

    -- **Double**: Two dashes (a)
    - - **Spaced**: Dash space dash (b)
    --- **Triple**: Three dashes (c)
    - **Good**: Single dash (d)
    """

    [%{items: items}] = parse(md)
    assert Enum.map(items, & &1.name) == ["Good"]
    assert hd(items).tags == ["d"]
  end

  test "a single tag in parentheses yields a one-element tags list" do
    md = """
    ## Single

    - **Solo**: Only one tag (only)
    """

    [%{items: [item]}] = parse(md)
    assert item.description == "Only one tag"
    assert item.tags == ["only"]
  end
end
```
