  test "blank lines are skipped entirely (no element emitted)", %{path: path} do
    File.write!(path, "\n" <> valid(%{"id" => 1}) <> "\n\n   \n" <> valid(%{"id" => 2}) <> "\n\n")

    results = path |> NdjsonStreamer.stream() |> Enum.to_list()

    assert results == [{:ok, %{"id" => 1}}, {:ok, %{"id" => 2}}]
  end