Implement the private `classify/1` function.

`classify/1` is the per-line categorizer that `step/2` dispatches on. It takes a
single `line` (a binary that has already been trimmed of trailing whitespace) and
returns a tag describing how that line should be interpreted. It must use the
module-level regexes `@heading_re`, `@item_re`, and `@bullet_re`, and return one
of the following, tested in this priority order:

- If the line matches `@heading_re` (capturing the run of `#` characters and the
  title text), inspect the length of the hash run. When there are **exactly two**
  `#`, return `{:heading, title}` with the title trimmed. Otherwise (one `#`, or
  three or more) return `:bad_heading`.
- Otherwise, if the line matches `@item_re` (capturing name, description, and the
  optional raw tags), return `{:item, item}` where `item` is produced by
  `build_item/1` from the captured groups.
- Otherwise, if the line matches `@bullet_re` (it starts at column zero with a
  dash and whitespace but is not a well-formed item), return `:malformed_item`.
- Otherwise, return `:ignore`.

Headings must be checked before items, and items before the bare-bullet fallback,
so that a malformed bullet is only reported once every stricter pattern has failed.

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
    # TODO
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