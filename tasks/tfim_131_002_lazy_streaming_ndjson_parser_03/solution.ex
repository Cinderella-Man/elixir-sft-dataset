  test "composes with Stream.take without forcing the whole file", %{path: path} do
    write_lines(path, for(i <- 1..1000, do: valid(%{"id" => i})))

    first_three =
      path
      |> NdjsonStreamer.stream()
      |> Stream.take(3)
      |> Enum.to_list()

    assert first_three == [
             {:ok, %{"id" => 1}},
             {:ok, %{"id" => 2}},
             {:ok, %{"id" => 3}}
           ]
  end