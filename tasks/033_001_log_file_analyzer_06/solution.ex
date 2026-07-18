  # Stream the file line by line, folding into a single accumulator. Any I/O
  # failure that only surfaces once the stream is pulled is converted into an
  # {:error, reason} tuple rather than an exception.
  defp stream_report(path) do
    report =
      path
      |> File.stream!(:line, [])
      |> Stream.map(&String.trim_trailing(&1, "\n"))
      |> Stream.map(&String.trim_trailing(&1, "\r"))
      |> Enum.reduce(initial_acc(), &process_line/2)
      |> build_report()

    {:ok, report}
  rescue
    error in File.Error -> {:error, error.reason}
  end