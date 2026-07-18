  defp resolve_store(conn, opts) do
    conn.private[:team_store] || Keyword.get(opts, :store) ||
      Keyword.get(conn.assigns[:router_opts] || [], :store)
  end