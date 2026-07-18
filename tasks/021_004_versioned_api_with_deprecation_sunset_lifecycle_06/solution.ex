  defp put_sunset(conn, version) do
    case Map.get(@sunsets, version) do
      nil -> conn
      date -> put_resp_header(conn, "sunset", date)
    end
  end