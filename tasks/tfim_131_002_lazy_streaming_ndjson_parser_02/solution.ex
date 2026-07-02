  test "stream/1 returns a lazy enumerable, not a list", %{path: path} do
    write_lines(path, for(i <- 1..5, do: valid(%{"id" => i})))

    stream = NdjsonStreamer.stream(path)

    refute is_list(stream)
    assert match?(%Stream{}, stream) or is_function(stream)
  end