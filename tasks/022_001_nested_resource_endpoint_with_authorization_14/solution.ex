  defp store(conn) do
    conn.private[:team_store] || Keyword.get(conn.assigns[:router_opts] || [], :store)
  end