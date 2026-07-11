  test "empty file yields an empty stream", %{path: path} do
    File.write!(path, "")

    assert path |> NdjsonStreamer.stream() |> Enum.to_list() == []
  end