  defp add_member(conn, store, team_id) do
    case read_body_params(conn) do
      {:ok, user_id, role, conn} ->
        case TeamStore.add_member_safe(store, team_id, user_id, role) do
          {:ok, uid} -> json(conn, 201, %{added: uid, role: role})
          {:error, :conflict} -> json(conn, 409, %{error: "conflict"})
          {:error, :not_found} -> json(conn, 404, %{error: "not_found"})
        end

      {:error, conn} ->
        json(conn, 400, %{error: "bad_request"})
    end
  end