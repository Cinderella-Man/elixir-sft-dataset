  test "sample_rows defaults to at most the first 100 data rows" do
    rows = List.duplicate("2020-01-15", 100)
    csv = Enum.join(["ts"] ++ rows ++ ["2020-01-15T10:00:00"], "\n") <> "\n"

    assert schema(csv) == %{"ts" => :date}
    assert schema(csv, sample_rows: 101) == %{"ts" => :datetime}
  end