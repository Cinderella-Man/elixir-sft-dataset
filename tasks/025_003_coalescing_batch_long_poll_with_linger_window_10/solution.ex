  @spec respond(Plug.Conn.t(), [term()]) :: Plug.Conn.t()
  defp respond(conn, payloads) do
    body = Jason.encode!(%{"notifications" => payloads, "count" => length(payloads)})

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, body)
  end