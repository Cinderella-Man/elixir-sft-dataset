  test "sample_rows defaults to 100 data rows" do
    body = Enum.map_join(1..100, "", fn i -> "#{i}\n" end)
    csv = "n\n" <> body <> "1\n"

    # the 101st data row repeats "1" but falls outside the default sample
    assert schema(csv) == %{"n" => %{type: :integer, nullable: false, unique: true}}

    assert schema(csv, sample_rows: 101) == %{
             "n" => %{type: :integer, nullable: false, unique: false}
           }
  end