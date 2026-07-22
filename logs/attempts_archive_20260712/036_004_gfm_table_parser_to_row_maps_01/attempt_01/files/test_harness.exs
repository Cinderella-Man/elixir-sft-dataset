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
    md = """
    | A | B |
    | 1 | 2 |
    """

    assert parse(md) == []
  end

  test "empty string returns empty list" do
    assert parse("") == []
  end

  test "handles CRLF line endings" do
    md = "| A | B |\r\n| --- | --- |\r\n| 1 | 2 |\r\n"
    assert [%{headers: ["A", "B"], rows: [%{"A" => "1", "B" => "2"}]}] = parse(md)
  end
end