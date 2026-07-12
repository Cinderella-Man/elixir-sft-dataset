# Fix the bug

The module below was written for the task that follows, but ONE behavior bug
slipped in. The test suite (not shown) fails with the report at the bottom.
Find the bug and fix it — change as little as possible; do not restructure
working code. Reply with the complete corrected module.

## The task the module implements

Write me an Elixir module called `MarkdownTables` that extracts every GitHub-Flavored-Markdown **table** in a document and returns each as structured row maps.

A table is a contiguous block of three parts:
1. A header row of pipe-delimited cells, e.g. `| Name | Age |`.
2. A separator row immediately beneath it, where every cell matches the delimiter pattern `:?-+:?` (e.g. `---`, `:---`, `---:`, `:---:`).
3. Zero or more data rows (each a pipe-delimited line) until the first line that is not a pipe row.

The single public function should be:
- `MarkdownTables.parse(markdown_string)` which accepts a binary and returns a list of table maps in document order:
  ```elixir
  [
    %{
      headers: ["Name", "Age"],
      alignments: [:left, :right],
      rows: [%{"Name" => "Alice", "Age" => "30"}]
    }
  ]
  ```

Parsing rules to implement:
- **Pipe rows**: leading and trailing `|` are optional; cells are the text between unescaped `|` characters, each trimmed of surrounding whitespace.
- **Escaped pipes**: a `\|` inside a cell is a literal `|` and does NOT split the cell.
- **Separator validation**: the row directly under the header only forms a table if it has the same number of cells as the header AND every cell matches `:?-+:?`. Otherwise the "header" line is not a table start and scanning continues from the next line.
- **Alignments**, derived per separator cell: `:---` → `:left`, `---:` → `:right`, `:---:` → `:center`, `---` → `:none`. The `alignments` list has one entry per header column.
- **Rows**: each data row is keyed by the header strings. A ragged row with **fewer** cells than headers pads the missing columns with `""`; a row with **more** cells than headers drops the extras.
- Lines that are not part of any table (prose, blank lines) are ignored.
- The empty string returns `[]`; a document with no valid table returns `[]`.

Give me the complete module in a single file. Use only the Elixir standard library — no external dependencies.

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
      {:error, table, remaining} -> [table | scan(remaining)]
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
      true -> :none
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
10 of 12 test(s) failed:

  * test parses a basic table with header, separator, and rows
      no case clause matching:
      
          {:ok,
           %{
             rows: [
               %{"Age" => "30", "Name" => "Alice"},
               %{"Age" => "25", "Name" => "Bob"}
             ],
             headers: ["Name", "Age"],
             alignments: [:none, :none]
           }, [""]}
      

  * test derives alignments from separator markers
      no case clause matching:
      
          {:ok,
           %{
             rows: [%{"C" => "2", "L" => "1", "R" => "3"}],
             headers: ["L", "C", "R"],
             alignments: [:left, :center, :right]
           }, [""]}
      

  * test supports rows without outer pipes
      no case clause matching:
      
          {:ok,
           %{
             rows: [%{"Age" => "30", "Name" => "Alice"}],
             headers: ["Name", "Age"],
             alignments: [:none, :none]
           }, [""]}
      

  * test pads ragged rows that have too few cells
      no case clause matching:
      
          {:ok,
           %{
             rows: [%{"Age" => "", "Name" => "Bob"}],
             headers: ["Name", "Age"],
             alignments: [:none, :none]
           }, [""]}
      

  (…6 more)
```
