# Add moduledoc, docs, and specs

Below: a correct, tested, undocumented module. Deliver the same module
fully documented — a `@moduledoc`, a per-public-function `@doc` and
`@spec`, and supporting `@type`s where useful. Behavior, names, structure:
unchanged. One file.

## The module

```elixir
defmodule MarkdownTables do
  @sep_re ~r/^:?-+:?$/

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
