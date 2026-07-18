  @spec store_auth(Plug.Conn.t(), any()) :: Plug.Conn.t()
  defp store_auth(conn, _opts) do
    AuthPlug.call(conn, AuthPlug.init(store: conn.private.team_store))
  end