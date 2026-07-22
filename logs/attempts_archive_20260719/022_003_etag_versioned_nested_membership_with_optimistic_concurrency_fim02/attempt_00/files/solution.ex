  defp with_user_id(conn, store, team_id, if_match) do
    case conn.body_params do
      %{"user_id" => user_id} when is_binary(user_id) ->
        apply_add(conn, store, team_id, user_id, parse_version(if_match))

      _ ->
        send_json(conn, 400, %{error: "bad_request"})
    end
  end