  @spec handle_add(Plug.Conn.t(), TeamStore.server(), String.t()) :: Plug.Conn.t()
  defp handle_add(conn, store, team_id) do
    case Plug.Conn.get_req_header(conn, "if-match") do
      [] ->
        send_json(conn, 428, %{error: "precondition_required"})

      [if_match | _] ->
        with_user_id(conn, store, team_id, if_match)
    end
  end