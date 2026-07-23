# Fix the bug

The module below was written for the task that follows, but ONE behavior bug
slipped in. The test suite (not shown) fails with the report at the bottom.
Find the bug and fix it — change as little as possible; do not restructure
working code. Reply with the complete corrected module.

## The task the module implements

Hey — I need you to write me an Elixir module called `MarkdownTables` that pulls every GitHub-Flavored-Markdown **table** out of a document and hands each one back as structured row maps.

The way I think about a table: it's a contiguous block made of three parts. First, a header row of pipe-delimited cells, e.g. `| Name | Age |`. Second, a separator row immediately beneath it, where every cell matches the delimiter pattern `:?-+:?` (so things like `---`, `:---`, `---:`, `:---:`). Third, zero or more data rows — each a pipe-delimited line — running until the first line that isn't a pipe row.

I only want one public function out of this: `MarkdownTables.parse(markdown_string)`, which takes a binary and returns a list of table maps in document order. Concretely, I'm expecting shapes like this back:

```elixir
[
  %{
    headers: ["Name", "Age"],
    alignments: [:left, :right],
    rows: [%{"Name" => "Alice", "Age" => "30"}]
  }
]
```

Here are the parsing rules I need you to implement, and I care about all of them:

For line endings, split the document on `\n`, and strip any trailing carriage return (`\r`) off each line so that `\r\n` (CRLF) input parses identically to `\n` input and no `\r` leaks into the cell text.

For pipe rows, the leading and trailing `|` are optional; the cells are the text between unescaped `|` characters, each trimmed of the whitespace around it.

On escaped pipes: a `\|` inside a cell is a literal `|` and must NOT split the cell.

For separator validation: the row directly under the header only forms a table if it has the same number of cells as the header AND every cell matches `:?-+:?`. If that doesn't hold, then that "header" line isn't a table start — keep scanning from the next line, because a later line can still turn out to be the header.

Alignments get derived per separator cell: `:---` → `:left`, `---:` → `:right`, `:---:` → `:center`, `---` → `:none`. The `alignments` list has exactly one entry per header column.

For rows, key each data row by the header strings. If a row is ragged with **fewer** cells than there are headers, pad the missing columns with `""`; if it has **more** cells than headers, drop the extras.

Anything that isn't part of a table — prose, blank lines — just ignore it. The empty string returns `[]`, and a document with no valid table also returns `[]`.

Give me the complete module in a single file, and stick to the Elixir standard library only — no external dependencies.

## The buggy module

```elixir
defmodule MarkdownTables do
  @moduledoc """
  Extracts GitHub-Flavored-Markdown tables from a document, returning each as a
  map of `%{headers: [...], alignments: [...], rows: [%{header => value}]}`.

  A table is a header pipe-row, a separator row whose cells all match `:?-+:?`,
  and the run of pipe-rows beneath it. Escaped `\\|` is treated as a literal pipe,
  ragged rows are padded/truncated to the header width, and non-table lines are
  ignored.
  """

  @sep_re ~r/^:?-+:?$/

  @doc """
  Parses `markdown` and returns a list of table maps in document order.

  Each table map has `:headers` (a list of column strings), `:alignments`
  (one of `:left`, `:right`, `:center`, or `:none` per column), and `:rows`
  (a list of maps keyed by the header strings). Ragged rows are padded with
  `""` or truncated to the header width. Returns `[]` when no table is found.

  ## Examples

      iex> MarkdownTables.parse("| Name | Age |\\n| --- | ---: |\\n| Alice | 30 |")
      [
        %{
          headers: ["Name", "Age"],
          alignments: [:none, :right],
          rows: [%{"Name" => "Alice", "Age" => "30"}]
        }
      ]

  """
  @spec parse(binary()) :: [map()]
  def parse(markdown) when is_binary(markdown) do
    markdown
    |> String.split("\n")
    |> Enum.map(&String.trim_trailing/1)
    |> scan()
  end

  # ---------------------------------------------------------------------------
  # Scan for table blocks
  # ---------------------------------------------------------------------------

  defp scan([_h, sep | rest] = lines) do
    case try_table(lines) do
      {:ok, table, remaining} -> [table | scan(remaining)]
      :no -> scan([sep | rest])
    end
  end

  defp scan([_ | rest]), do: scan(rest)
  defp scan([]), do: []

  defp try_table([h, sep | rest]) do
    if pipe_row?(h) do
      headers = split_row(h)
      sep_cells = split_row(sep)

      if valid_separator?(sep_cells, length(headers)) do
        {rows, remaining} = take_rows(rest, [])

        table = %{
          headers: headers,
          alignments: Enum.map(sep_cells, &alignment/1),
          rows: Enum.map(rows, &row_map(headers, &1))
        }

        {:ok, table, remaining}
      else
        :no
      end
    else
      :no
    end
  end

  # Consume consecutive pipe rows as data rows.
  defp take_rows([line | rest], acc) do
    if pipe_row?(line) do
      take_rows(rest, [split_row(line) | acc])
    else
      {Enum.reverse(acc), [line | rest]}
    end
  end

  defp take_rows([], acc), do: {Enum.reverse(acc), []}

  # ---------------------------------------------------------------------------
  # Row / cell parsing
  # ---------------------------------------------------------------------------

  defp pipe_row?(line) do
    line
    |> String.trim()
    |> String.replace("\\|", "")
    |> String.contains?("|")
  end

  defp valid_separator?(cells, n) do
    length(cells) == n and n > 0 and Enum.all?(cells, &Regex.match?(@sep_re, &1))
  end

  defp alignment(cell) do
    left = String.starts_with?(cell, ":")
    right = String.ends_with?(cell, ":")

    cond do
      left and right -> :center
      right -> :right
      left -> :left
      false -> :none
    end
  end

  defp split_row(line) do
    line
    |> String.trim()
    |> strip_edges()
    |> String.replace("\\|", "\x00")
    |> String.split("|")
    |> Enum.map(fn cell ->
      cell |> String.replace("\x00", "|") |> String.trim()
    end)
  end

  defp strip_edges(s) do
    s
    |> strip_leading_pipe()
    |> strip_trailing_pipe()
  end

  defp strip_leading_pipe("|" <> rest), do: rest
  defp strip_leading_pipe(s), do: s

  defp strip_trailing_pipe(s) do
    if String.ends_with?(s, "|") and not String.ends_with?(s, "\\|") do
      binary_part(s, 0, byte_size(s) - 1)
    else
      s
    end
  end

  defp row_map(headers, cells) do
    headers
    |> Enum.with_index()
    |> Enum.map(fn {header, i} -> {header, Enum.at(cells, i, "")} end)
    |> Map.new()
  end
end
```

## Failing test report

```
9 of 12 test(s) failed:

  * test parses a basic table with header, separator, and rows
      no cond clause evaluated to a truthy value

  * test supports rows without outer pipes
      no cond clause evaluated to a truthy value

  * test pads ragged rows that have too few cells
      no cond clause evaluated to a truthy value

  * test drops extra cells in rows with too many columns
      no cond clause evaluated to a truthy value

  (…5 more)
```
