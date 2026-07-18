  @spec store(Plug.Conn.t()) :: TeamStore.server()
  defp store(conn), do: Map.get(conn.private, :team_store, TeamStore)