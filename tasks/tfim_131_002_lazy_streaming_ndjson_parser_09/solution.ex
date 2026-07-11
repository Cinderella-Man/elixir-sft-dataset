  test "malformed line surfaces as {:error, {:invalid_json, raw}} and continues", %{path: path} do
    write_lines(path, [
      valid(%{"id" => 1}),
      "{not valid json",
      valid(%{"id" => 2})
    ])

    results = path |> NdjsonStreamer.stream() |> Enum.to_list()

    assert results == [
             {:ok, %{"id" => 1}},
             {:error, {:invalid_json, "{not valid json"}},
             {:ok, %{"id" => 2}}
           ]
  end