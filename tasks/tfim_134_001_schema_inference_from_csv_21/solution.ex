  test "sample_rows defaults to exactly 100 data rows" do
    rows = Enum.map(1..100, fn _ -> "1" end) ++ ["3.5"]
    csv = Enum.join(["n" | rows], "\n") <> "\n"

    assert schema(csv) == %{"n" => :integer}
    assert schema(csv, sample_rows: 101) == %{"n" => :float}
  end