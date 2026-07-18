  test "a non-empty field failing both type and format reports both errors" do
    # "year" must parse as an integer AND match a 4-digit pattern. The value
    # "20xx" violates both checks, so both errors must be reported for that
    # one field — not just the first one found.
    schema = [
      field("year", type: :integer, format: ~r/^\d{4}$/),
      field("label")
    ]

    csv = """
    year,label
    20xx,annual
    """

    assert {:ok, [], errors} = CsvImporter.import_string(csv, schema)

    year_msgs =
      errors
      |> Enum.filter(fn {row, f, _msg} -> row == 1 and f == "year" end)
      |> Enum.map(fn {_row, _f, msg} -> msg end)

    assert length(year_msgs) == 2
    assert Enum.any?(year_msgs, &(&1 =~ "integer"))
    assert Enum.any?(year_msgs, &(&1 =~ "format"))
  end