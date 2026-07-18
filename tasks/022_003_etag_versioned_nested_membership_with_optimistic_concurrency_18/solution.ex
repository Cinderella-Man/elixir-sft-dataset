  @spec send_json(Plug.Conn.t(), non_neg_integer(), map()) :: Plug.Conn.t()
  defp send_json(conn, status, payload) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, Jason.encode!(payload))
  end