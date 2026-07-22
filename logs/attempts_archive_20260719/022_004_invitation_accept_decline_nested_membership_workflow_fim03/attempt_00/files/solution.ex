defp with_team_and_member(conn, store, team_id, fun) do
  current = conn.assigns.current_user

  cond do
    not TeamStore.team_exists?(store, team_id) ->
      send_json(conn, 404, %{error: "not_found"})

    not TeamStore.is_member?(store, team_id, current) ->
      send_json(conn, 403, %{error: "forbidden"})

    true ->
      fun.()
  end
end