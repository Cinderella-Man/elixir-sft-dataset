  # Attempt to parse a single non-blank line into a validated entry map.
  # Returns {:ok, entry} or :error.
  defp parse_line(trimmed) do
    with {:ok, obj} when is_map(obj) <- Jason.decode(trimmed),
         {:ok, ts_string} <- fetch_string(obj, "timestamp"),
         {:ok, level} <- fetch_string(obj, "level"),
         {:ok, message} <- fetch_string(obj, "message"),
         true <- Map.has_key?(obj, "metadata") && is_map(obj["metadata"]),
         {:ok, dt} <- parse_timestamp(ts_string) do
      {:ok, %{timestamp: dt, level: level, message: message}}
    else
      _ -> :error
    end
  end