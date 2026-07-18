  test "handles 500 rows correctly" do
    schema = [field("id", type: :integer), field("val")]

    header = "id,val"

    rows =
      Enum.map(1..500, fn i ->
        if rem(i, 50) == 0 do
          "bad,row#{i}"
        else
          "#{i},row#{i}"
        end
      end)

    csv = Enum.join([header | rows], "\n")

    assert {:ok, valid, errors} = CsvImporter.import_string(csv, schema)
    assert length(valid) == 490
    assert length(errors) == 10

    # All errors should be on every 50th row
    error_rows = Enum.map(errors, fn {row, _f, _m} -> row end) |> Enum.sort()
    assert error_rows == Enum.map(1..10, &(&1 * 50))
  end