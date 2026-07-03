  defp add_member(conn, store, team_id) do
    case read_user_id(conn) do
      {:ok, new_user_id, conn} ->
        case TeamStore.add_member_safe(store, team_id, new_user_id) do
          {:ok, user_id} -> json(conn, 201, %{added: user_id})
          {:error, :conflict} -> json(conn, 409, %{error: "conflict"})
          {:error, :not_found} -> json(conn, 404, %{error: "not_found"})
        end

      {:error, conn} ->
        json(conn, 400, %{error: "bad_request"})
    end
  end