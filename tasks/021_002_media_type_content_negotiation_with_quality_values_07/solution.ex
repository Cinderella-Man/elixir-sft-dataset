  defp resolve(conn, accept, supported, default) do
    version =
      accept
      |> parse_accept(default)
      |> Enum.filter(fn {v, _q} -> v in supported end)
      |> best_version()

    case version do
      nil ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(406, Jason.encode!(%{error: "unsupported version", supported: supported}))
        |> halt()

      v ->
        assign(conn, :api_version, v)
    end
  end