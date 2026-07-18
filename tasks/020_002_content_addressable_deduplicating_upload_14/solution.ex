  @spec json(Plug.Conn.t(), non_neg_integer(), map()) :: Plug.Conn.t()
  defp json(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end