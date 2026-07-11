  test "decodes objects into string-keyed maps", %{path: path} do
    write_lines(path, for(i <- 1..3, do: valid(%{"id" => i, "value" => "item-#{i}"})))

    values =
      path
      |> NdjsonStreamer.stream()
      |> Enum.map(fn {:ok, v} -> v end)

    assert values == [
             %{"id" => 1, "value" => "item-1"},
             %{"id" => 2, "value" => "item-2"},
             %{"id" => 3, "value" => "item-3"}
           ]
  end