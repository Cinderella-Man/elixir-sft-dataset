# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule MarkdownReport do
  @moduledoc """
  Strict, diagnostic Markdown-to-structured-data parser.

  Parses `## category` sections and their `- **Name**: description (tags)` bullet
  items, and additionally reports — with 1-indexed line numbers — every line it
  could not interpret: unsupported headings, malformed bullets, orphan items
  (before any heading), and duplicate categories (whose sections are suppressed).
  """

  @heading_re ~r/^(#+)\s+(.+?)\s*$/
  @item_re ~r/^-\s+\*\*(.+?)\*\*:\s+(.*?)(?:\s+\(([^)]*)\))?\s*$/
  @bullet_re ~r/^-\s+/

  @doc """
  Parses a Markdown `binary` into structured categories and diagnostic errors.

  Returns a map with two keys:

    * `:categories` — a list of `%{category: name, items: [...]}` maps in document
      order, each item shaped `%{name: n, description: d, tags: [t]}`;
    * `:errors` — a list of `%{line: idx, content: line, reason: reason}` maps in
      ascending line order, where `reason` is one of `:unsupported_heading`,
      `:malformed_item`, `:orphan_item`, or `:duplicate_category`.

  The empty string returns `%{categories: [], errors: []}`.
  """
  @spec parse(binary()) :: %{categories: [map()], errors: [map()]}
  def parse(markdown) when is_binary(markdown) do
    init = %{cats: [], current: nil, errors: [], seen: MapSet.new()}

    final =
      markdown
      |> String.split("\n")
      |> Enum.map(&String.trim_trailing/1)
      |> Enum.with_index(1)
      |> Enum.reduce(init, &step/2)
      |> flush()

    %{categories: Enum.reverse(final.cats), errors: Enum.reverse(final.errors)}
  end

  # ---------------------------------------------------------------------------
  # Per-line dispatch
  # ---------------------------------------------------------------------------

  defp step({line, idx}, acc) do
    case classify(line) do
      {:heading, title} -> handle_heading(title, line, idx, acc)
      :bad_heading -> add_error(acc, idx, line, :unsupported_heading)
      {:item, item} -> handle_item(item, line, idx, acc)
      :malformed_item -> add_error(acc, idx, line, :malformed_item)
      :ignore -> acc
    end
  end

  defp classify(line) do
    cond do
      caps = Regex.run(@heading_re, line, capture: :all_but_first) ->
        [hashes, title] = caps
        if String.length(hashes) == 2, do: {:heading, String.trim(title)}, else: :bad_heading

      caps = Regex.run(@item_re, line, capture: :all_but_first) ->
        {:item, build_item(caps)}

      Regex.match?(@bullet_re, line) ->
        :malformed_item

      true ->
        :ignore
    end
  end

  # ---------------------------------------------------------------------------
  # State transitions
  # ---------------------------------------------------------------------------

  defp handle_heading(title, line, idx, acc) do
    acc = flush(acc)

    if MapSet.member?(acc.seen, title) do
      %{acc | current: :suppressed}
      |> add_error(idx, line, :duplicate_category)
    else
      %{acc | current: %{category: title, items: []}, seen: MapSet.put(acc.seen, title)}
    end
  end

  defp handle_item(item, line, idx, acc) do
    case acc.current do
      %{} = node -> %{acc | current: %{node | items: [item | node.items]}}
      :suppressed -> acc
      nil -> add_error(acc, idx, line, :orphan_item)
    end
  end

  defp add_error(acc, idx, line, reason) do
    %{acc | errors: [%{line: idx, content: line, reason: reason} | acc.errors]}
  end

  # Flush the currently open category (if any) into the result list.
  defp flush(%{current: %{} = node} = acc) do
    %{acc | cats: [finalize(node) | acc.cats], current: nil}
  end

  defp flush(acc), do: %{acc | current: nil}

  defp finalize(%{category: category, items: items}) do
    %{category: category, items: Enum.reverse(items)}
  end

  # ---------------------------------------------------------------------------
  # Item building
  # ---------------------------------------------------------------------------

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
end
```

## Test harness — implement the `# TODO` test

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
    # TODO
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
