  def stream(file_path) do
    file_path
    |> File.stream!([], :line)
    |> Stream.map(&String.trim/1)
    |> Stream.reject(&(&1 == ""))
    |> Stream.map(&decode_line/1)
  end