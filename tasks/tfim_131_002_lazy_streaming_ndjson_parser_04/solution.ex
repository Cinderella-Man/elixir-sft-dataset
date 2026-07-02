  test "yields {:ok, value} for every well-formed line", %{path: path} do
    write_lines(path, for(i <- 1..25, do: valid(%{"id" => i})))

    results = path |> NdjsonStreamer.stream() |> Enum.to_list()

    assert length(results) == 25
    assert Enum.all?(results, &match?({:ok, _}, &1))
    assert Enum.map(results, fn {:ok, v} -> v["id"] end) == Enum.to_list(1..25)
  end