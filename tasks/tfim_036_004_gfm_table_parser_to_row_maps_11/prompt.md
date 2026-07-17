# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

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

## Test harness — implement the `# TODO` test

```elixir
defmodule MarkdownTablesTest do
  use ExUnit.Case, async: false

  defp parse(md), do: MarkdownTables.parse(md)

  test "parses a basic table with header, separator, and rows" do
    md = """
    | Name | Age |
    | --- | --- |
    | Alice | 30 |
    | Bob | 25 |
    """

    assert parse(md) == [
             %{
               headers: ["Name", "Age"],
               alignments: [:none, :none],
               rows: [
                 %{"Name" => "Alice", "Age" => "30"},
                 %{"Name" => "Bob", "Age" => "25"}
               ]
             }
           ]
  end

  test "derives alignments from separator markers" do
    md = """
    | L | C | R |
    | :--- | :---: | ---: |
    | 1 | 2 | 3 |
    """

    [table] = parse(md)
    assert table.alignments == [:left, :center, :right]
  end

  test "supports rows without outer pipes" do
    md = """
    Name | Age
    --- | ---
    Alice | 30
    """

    assert [%{headers: ["Name", "Age"], rows: [%{"Name" => "Alice", "Age" => "30"}]}] = parse(md)
  end

  test "pads ragged rows that have too few cells" do
    md = """
    | Name | Age |
    | --- | --- |
    | Bob |
    """

    [%{rows: [row]}] = parse(md)
    assert row == %{"Name" => "Bob", "Age" => ""}
  end

  test "drops extra cells in rows with too many columns" do
    md = """
    | A | B |
    | --- | --- |
    | 1 | 2 | 3 |
    """

    [%{rows: [row]}] = parse(md)
    assert row == %{"A" => "1", "B" => "2"}
  end

  test "escaped pipes do not split cells" do
    md = """
    | Expr | Note |
    | --- | --- |
    | a \\| b | logical or |
    """

    [%{rows: [row]}] = parse(md)
    assert row == %{"Expr" => "a | b", "Note" => "logical or"}
  end

  test "trims whitespace inside cells" do
    md = """
    |   Key   |   Value   |
    | --- | --- |
    |   x   |   y   |
    """

    [table] = parse(md)
    assert table.headers == ["Key", "Value"]
    assert table.rows == [%{"Key" => "x", "Value" => "y"}]
  end

  test "ignores surrounding prose and blank lines" do
    md = """
    Some intro text.

    | A | B |
    | --- | --- |
    | 1 | 2 |

    Trailing note.
    """

    assert [%{headers: ["A", "B"], rows: [%{"A" => "1", "B" => "2"}]}] = parse(md)
  end

  test "parses multiple tables in document order" do
    md = """
    | X |
    | --- |
    | 1 |

    | Y |
    | --- |
    | 2 |
    """

    result = parse(md)
    assert length(result) == 2
    assert Enum.map(result, & &1.headers) == [["X"], ["Y"]]
  end

  test "a header without a valid separator is not a table" do
    # TODO
  end

  test "empty string returns empty list" do
    assert parse("") == []
  end

  test "handles CRLF line endings" do
    md = "| A | B |\r\n| --- | --- |\r\n| 1 | 2 |\r\n"
    assert [%{headers: ["A", "B"], rows: [%{"A" => "1", "B" => "2"}]}] = parse(md)
  end

  test "rescans from the next line so a later line can become the header" do
    md = """
    | A | B |
    | C | D |
    | --- | --- |
    | 1 | 2 |
    """

    assert parse(md) == [
             %{
               headers: ["C", "D"],
               alignments: [:none, :none],
               rows: [%{"C" => "1", "D" => "2"}]
             }
           ]
  end

  test "separator with a different cell count than the header forms no table" do
    md = """
    | A | B |
    | --- |
    | 1 | 2 |
    """

    assert parse(md) == []
  end

  test "header and separator alone yield a table with zero rows" do
    md = """
    | A | B |
    | --- | :---: |
    """

    assert parse(md) == [%{headers: ["A", "B"], alignments: [:none, :center], rows: []}]
  end

  test "a non-pipe line ends the table and later pipe rows are excluded" do
    md = """
    | A |
    | --- |
    | 1 |
    prose interrupts here
    | 2 |
    """

    assert parse(md) == [%{headers: ["A"], alignments: [:none], rows: [%{"A" => "1"}]}]
  end

  test "escaped pipes in a header cell keep one column and key the rows" do
    md = """
    | a \\| b | c |
    | --- | --- |
    | 1 | 2 |
    """

    [table] = parse(md)
    assert table.headers == ["a | b", "c"]
    assert table.rows == [%{"a | b" => "1", "c" => "2"}]
  end
end
```
