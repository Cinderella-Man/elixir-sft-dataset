  test "abort then resume past the poison line completes the run", %{path: path} do
    encoded =
      for i <- 1..10 do
        if i == 4, do: "{broken", else: valid(%{"id" => i})
      end

    write_array(path, encoded)

    {:ok, c1} = Collector.start_link()

    assert {:error, :too_many_errors, s1} =
             ResumableJsonStreamer.process(path, Collector.handler(c1), max_errors: 0)

    assert s1.last_index == 4
    assert Enum.map(Collector.items(c1), & &1["id"]) == [1, 2, 3]

    {:ok, c2} = Collector.start_link()

    assert {:ok, s2} =
             ResumableJsonStreamer.process(path, Collector.handler(c2),
               resume_from: s1.last_index,
               max_errors: 0
             )

    assert s2.aborted == false
    assert s2.processed == 6
    assert Enum.map(Collector.items(c2), & &1["id"]) == [5, 6, 7, 8, 9, 10]
  end