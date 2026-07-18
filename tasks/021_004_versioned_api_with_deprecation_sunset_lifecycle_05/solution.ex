  defp put_deprecation_headers(conn, version) do
    conn
    |> put_resp_header("deprecation", "true")
    |> put_sunset(version)
    |> put_resp_header("warning", ~s(299 - "Deprecated API version #{version}"))
  end