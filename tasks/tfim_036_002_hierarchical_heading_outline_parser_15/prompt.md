# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule MarkdownOutline do
  @moduledoc """
  Parses a subset of Markdown into a nested outline tree driven by heading depth.

  Headings `#`..`######` create nodes; a heading deeper than the currently open
  node becomes its child, while a heading at the same or shallower level closes
  the branch and starts a sibling. Bullet items of the form
  `- **Name**: description (tag1, tag2)` attach to the deepest open node.
  """

  # One to (potentially) many "#" followed by whitespace and title text.
  @heading_re ~r/^(#+)\s+(.+?)\s*$/

  # Top-level bullet item: exactly one leading "-", a bold name, colon, description,
  # and an optional trailing "(tags)" group.
  @item_re ~r/^-\s+\*\*(.+?)\*\*:\s+(.*?)(?:\s+\(([^)]*)\))?\s*$/

  @doc """
  Parses `markdown` into a list of top-level outline node maps in document order.

  Each node is a map with `:title`, `:level`, `:items`, and `:children`. Bullet
  items attach to the deepest open node, and headings nest by relative depth.
  Returns `[]` for an empty document.
  """
  @spec parse(binary()) :: [map()]
  def parse(markdown) when is_binary(markdown) do
    {roots, stack} =
      markdown
      |> String.split("\n")
      |> Enum.map(&String.trim_trailing/1)
      |> Enum.map(&classify/1)
      |> Enum.reduce({[], []}, &step/2)

    finalize_stack(stack, roots)
  end

  # ---------------------------------------------------------------------------
  # Classification
  # ---------------------------------------------------------------------------

  defp classify(line) do
    cond do
      caps = Regex.run(@heading_re, line, capture: :all_but_first) ->
        [hashes, title] = caps
        level = String.length(hashes)
        if level <= 6, do: {:heading, level, String.trim(title)}, else: :ignore

      caps = Regex.run(@item_re, line, capture: :all_but_first) ->
        {:item, build_item(caps)}

      true ->
        :ignore
    end
  end

  defp build_item([name, description]), do: make(name, description, nil)
  defp build_item([name, description, raw]), do: make(name, description, raw)

  defp make(name, description, raw) do
    %{name: String.trim(name), description: String.trim(description), tags: tags(raw)}
  end

  defp tags(nil), do: []
  defp tags(""), do: []

  defp tags(raw) do
    raw
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  # ---------------------------------------------------------------------------
  # Tree construction via an explicit stack of open nodes
  # ---------------------------------------------------------------------------
  #
  # {roots, stack}
  #   roots – completed top-level nodes, reversed
  #   stack – path from root to the deepest currently open node (head = deepest)
  #

  defp step({:item, item}, {roots, [top | rest]}) do
    {roots, [%{top | items: [item | top.items]} | rest]}
  end

  defp step({:item, _item}, {roots, []}), do: {roots, []}

  defp step({:heading, level, title}, {roots, stack}) do
    {roots, stack} = close_until(level, roots, stack)
    node = %{title: title, level: level, items: [], children: []}
    {roots, [node | stack]}
  end

  defp step(:ignore, acc), do: acc

  # Close (and attach) every open node whose level is >= the incoming level.
  defp close_until(level, roots, [%{level: tl} = top | rest]) when tl >= level do
    {roots, rest} = attach(top, roots, rest)
    close_until(level, roots, rest)
  end

  defp close_until(_level, roots, stack), do: {roots, stack}

  # Finalise `node` and attach it as a child of the next open node, or as a root.
  defp attach(node, roots, [parent | rest]) do
    {roots, [%{parent | children: [finalize(node) | parent.children]} | rest]}
  end

  defp attach(node, roots, []) do
    {[finalize(node) | roots], []}
  end

  # Flush any remaining open nodes at end-of-document.
  defp finalize_stack([], roots), do: Enum.reverse(roots)

  defp finalize_stack([top | rest], roots) do
    {roots, rest} = attach(top, roots, rest)
    finalize_stack(rest, roots)
  end

  defp finalize(%{items: items, children: children} = node) do
    %{node | items: Enum.reverse(items), children: Enum.reverse(children)}
  end
end
```

## Test harness — implement the `# TODO` test

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
    # TODO
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
