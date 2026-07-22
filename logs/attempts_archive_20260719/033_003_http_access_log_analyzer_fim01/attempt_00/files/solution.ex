  defp parse_line(trimmed) do
    with {:ok, obj} when is_map(obj) <- Jason.decode(trimmed),
         {:ok, ts_string} <- fetch_string(obj, "timestamp"),
         {:ok, method} <- fetch_string(obj, "method"),
         {:ok, req_path} <- fetch_string(obj, "path"),
         {:ok, status_code} <- fetch_integer(obj, "status_code"),
         {:ok, duration_ms} <- fetch_number(obj, "duration_ms"),
         {:ok, dt} <- parse_timestamp(ts_string) do
      {:ok,
       %{
         timestamp: dt,
         method: method,
         path: req_path,
         status_code: status_code,
         duration_ms: duration_ms
       }}
    else
      _ -> :error
    end
  end