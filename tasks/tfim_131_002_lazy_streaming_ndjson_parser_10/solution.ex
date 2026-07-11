  test "caller can partition ok/error using ordinary stream functions", %{path: path} do
    write_lines(path, [
      valid(%{"id" => 1}),
      "garbage(((",
      valid(%{"id" => 2}),
      "]][[",
      valid(%{"id" => 3})
    ])

    {oks, errors} =
      path
      |> NdjsonStreamer.stream()
      |> Enum.split_with(&match?({:ok, _}, &1))

    assert Enum.map(oks, fn {:ok, v} -> v["id"] end) == [1, 2, 3]
    assert length(errors) == 2
    assert Enum.all?(errors, &match?({:error, {:invalid_json, _}}, &1))
  end