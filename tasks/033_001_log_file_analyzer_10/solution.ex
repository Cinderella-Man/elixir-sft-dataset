  # Parse an ISO 8601 string into a DateTime using the standard library.
  # DateTime.from_iso8601/1 handles offsets; we normalise to UTC.
  defp parse_timestamp(ts_string) do
    case DateTime.from_iso8601(ts_string) do
      {:ok, dt, _offset} ->
        {:ok, DateTime.shift_zone!(dt, "Etc/UTC")}

      {:error, _} ->
        :error
    end
  end