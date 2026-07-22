@spec handle_invite(Plug.Conn.t(), TeamStore.server(), String.t()) :: Plug.Conn.t()
defp handle_invite(conn, store, team_id) do
  case conn.body_params do
    %{"user_id" => user_id} when is_binary(user_id) ->
      case TeamStore.invite_member(store, team_id, user_id) do
        {:ok, id} -> send_json(conn, 201, %{invited: id})
        {:error, :conflict} -> send_json(conn, 409, %{error: "conflict"})
        {:error, :already_invited} -> send_json(conn, 409, %{error: "already_invited"})
        {:error, :not_found} -> send_json(conn, 404, %{error: "not_found"})
      end

    _ ->
      send_json(conn, 400, %{error: "bad_request"})
  end
end