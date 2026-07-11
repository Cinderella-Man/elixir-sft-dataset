  test "decodes different JSON value shapes", %{path: path} do
    write_lines(path, [
      valid(%{"kind" => "object"}),
      valid([1, 2, 3]),
      valid("a string"),
      valid(42),
      valid(true),
      valid(nil)
    ])

    values = path |> NdjsonStreamer.stream() |> Enum.map(fn {:ok, v} -> v end)

    assert values == [%{"kind" => "object"}, [1, 2, 3], "a string", 42, true, nil]
  end