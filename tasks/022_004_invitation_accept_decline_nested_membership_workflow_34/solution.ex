  @spec with_own_invitation(
          Plug.Conn.t(),
          TeamStore.server(),
          String.t(),
          String.t(),
          (-> Plug.Conn.t())
        ) :: Plug.Conn.t()
  defp with_own_invitation(conn, store, team_id, user_id, fun) do
    current = conn.assigns.current_user

    cond do
      not TeamStore.team_exists?(store, team_id) ->
        send_json(conn, 404, %{error: "not_found"})

      current != user_id ->
        send_json(conn, 403, %{error: "forbidden"})

      true ->
        fun.()
    end
  end