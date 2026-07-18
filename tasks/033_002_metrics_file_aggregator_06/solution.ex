  # Opening the path (rather than only stat-ing it) rejects directories,
  # permission problems and other non-streamable entries up front.
  defp ensure_readable(path) do
    case File.open(path, [:read]) do
      {:ok, io_device} ->
        File.close(io_device)
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end