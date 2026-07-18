# Bring this working module up to house style

I asked for the following:

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

Here is my implementation. It compiles and passes every test — the behavior
is correct — but it was rejected by the style review:

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

The style review said:

```
The solution is green but does not meet the house style: no @doc on any public function. Fix solution.ex so it has a `@moduledoc`, an `@spec` and `@doc` on public functions, no `TODO` markers, and compiles with ZERO warnings. Keep the behavior identical and do not weaken test_harness.exs.
```

Fix every finding in the review WITHOUT changing any behavior: the module
must keep passing exactly the tests it passes now. Give me the complete
corrected module in a single file.
<!-- minted from logs/attempts/036_004_gfm_table_parser_to_row_maps_01/attempt_0 -->
