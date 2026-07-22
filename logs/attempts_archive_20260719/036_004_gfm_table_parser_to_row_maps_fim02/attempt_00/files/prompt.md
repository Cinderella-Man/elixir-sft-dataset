Implement the private `try_table/1` function.

It receives the remaining document lines as a list whose first two elements are
destructured as the candidate header line `h` and the candidate separator line
`sep` (i.e. the clause head matches `[h, sep | rest]`). Its job is to decide
whether a valid table begins at `h`/`sep` and, if so, build the table map.

It must:

- Return `:no` immediately if `h` is not a pipe row (use `pipe_row?/1`).
- Otherwise, split the header line into `headers` and the separator line into
  `sep_cells` using `split_row/1`.
- Validate the separator with `valid_separator?/2`, passing `sep_cells` and the
  number of headers (`length(headers)`). If it is not a valid separator, return
  `:no`.
- When the separator is valid, consume the data rows that follow by calling
  `take_rows(rest, [])`, which returns `{rows, remaining}` — the collected data
  rows (each already split into cells) and the leftover lines.
- Build and return `{:ok, table, remaining}` where `table` is a map with:
  - `:headers` — the `headers` list.
  - `:alignments` — `sep_cells` mapped through `alignment/1`.
  - `:rows` — each collected row turned into a map via `row_map(headers, &1)`.

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
    # TODO
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