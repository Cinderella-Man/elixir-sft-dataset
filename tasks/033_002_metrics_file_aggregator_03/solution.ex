  defp parse_line(trimmed) do
    with {:ok, obj} when is_map(obj) <- Jason.decode(trimmed),
         {:ok, ts_string} <- fetch_string(obj, "timestamp"),
         {:ok, name} <- fetch_nonempty_string(obj, "name"),
         {:ok, value} <- fetch_number(obj, "value"),
         {:ok, tags} <- fetch_tags(obj, "tags"),
         {:ok, dt} <- parse_timestamp(ts_string) do
      {:ok, %{timestamp: dt, name: name, value: value, tags: tags}}
    else
      _ -> :error
    end
  end