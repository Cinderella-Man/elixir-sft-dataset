# Debug and repair this module

A colleague shipped the module below for the task described next, and one
behavior bug made it through review. The test suite (not shown here)
produces the failure report at the bottom. Track the bug down and repair
it — keep the diff minimal and leave working code exactly as it is. Reply
with the complete corrected module.

## What the module is supposed to do

# MarkdownReport: Diagnostic Markdown Category Parser — Specification

## Overview

This document specifies an Elixir module named `MarkdownReport` that parses a Markdown document into structured categories **and reports every line it could not interpret**, with line numbers.

It defines a strict, diagnostic variant: rather than silently ignoring malformed content, it collects errors so a caller can surface them.

The document format follows the same conventions as a flat category parser:
- `## Heading` lines (exactly two `#`) define category names.
- Bullet items underneath a heading follow the format: `- **Item Name**: description (tag1, tag2)`.
- Tags are optional — an item may end without parentheses (then `tags: []`).
- Blank lines and arbitrary prose are silently ignored (they are not errors).

The module must be delivered as a complete module in a single file. It must use only the Elixir standard library — no external dependencies.

## API

The single public function is:
- `MarkdownReport.parse(markdown_string)` which accepts a binary and returns a map:
  ```elixir
  %{
    categories: [
      %{category: "Name", items: [%{name: "n", description: "d", tags: ["t"]}]}
    ],
    errors: [
      %{line: 3, content: "- oops", reason: :malformed_item}
    ]
  }
  ```

## Edge cases

Diagnostic rules to implement (line numbers are 1-indexed against the original document, before any splitting on the next heading):
- **`:unsupported_heading`** — a heading with one `#` (H1) or three-plus `#` (H3+). It is reported and does **not** open a category, but it also does **not** close the currently open category (a following item still attaches to that category).
- **`:malformed_item`** — a line that starts at column zero with `- ` (a single dash and whitespace) but does not match the `- **Name**: description` format. (Space-indented / nested bullets are NOT reported — they are silently ignored.)
- **`:orphan_item`** — a well-formed bullet item that appears before any `##` heading has opened a category. It is reported and discarded.
- **`:duplicate_category`** — a `##` heading whose (trimmed) title equals one already seen. It is reported, the earlier category is flushed, and the duplicate section is **suppressed**: bullet items under it are silently ignored (not reported as orphans) until the next distinct heading.

Additional requirements:
- `categories` are in document order; items within a category are in document order.
- Every reported error carries the original (trailing-whitespace-trimmed) line content and its 1-indexed line number; `errors` are in ascending line order.
- Input may use `\n` or `\r\n` line endings; each line's trailing whitespace (including a trailing carriage return) is stripped before it is classified, so CRLF documents parse identically to LF ones.
- Tags are trimmed individually and empty tags dropped; category titles are trimmed.
- The empty string returns `%{categories: [], errors: []}`.

## The buggy module

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
      |> Enum.with_index(2)
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

## Failing test report

```
5 of 11 test(s) failed:

  * test malformed bullet reports line number and reason
      
      
      Assertion with == failed
      code:  assert errors == [%{line: 2, content: "- just a plain bullet", reason: :malformed_item}]
      left:  [%{line: 3, reason: :malformed_item, content: "- just a plain bullet"}]
      right: [%{line: 2, reason: :malformed_item, content: "- just a plain bullet"}]
      

  * test orphan item before any heading is reported and discarded
      
      
      Assertion with == failed
      code:  assert errors == [%{line: 1, content: "- **Orphan**: lost (x)", reason: :orphan_item}]
      left:  [%{line: 2, reason: :orphan_item, content: "- **Orphan**: lost (x)"}]
      right: [%{line: 1, reason: :orphan_item, content: "- **Orphan**: lost (x)"}]
      

  * test unsupported headings are reported but do not close the open category
      
      
      Assertion with == failed
      code:  assert reasons == [{1, :unsupported_heading}, {3, :unsupported_heading}]
      left:  [{2, :unsupported_heading}, {4, :unsupported_heading}]
      right: [{1, :unsupported_heading}, {3, :unsupported_heading}]
      

  * test duplicate category is reported and its section suppressed silently
      
      
      Assertion with == failed
      code:  assert errors == [%{line: 3, content: "## A", reason: :duplicate_category}]
      left:  [%{line: 4, reason: :duplicate_category, content: "## A"}]
      right: [%{line: 3, reason: :duplicate_category, content: "## A"}]
      

  (…1 more)
```
