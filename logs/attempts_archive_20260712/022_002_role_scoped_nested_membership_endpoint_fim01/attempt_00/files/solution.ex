  defp remove_member(conn, store, team_id, target_id, req_role) do
    case TeamStore.role_of(store, team_id, target_id) do
      :error ->
        json(conn, 404, %{error: "not_found"})

      {:ok, "owner"} when req_role != "owner" ->
        json(conn, 403, %{error: "forbidden"})

      {:ok, _} ->
        case TeamStore.remove_member_safe(store, team_id, target_id) do
          {:ok, uid} -> json(conn, 200, %{removed: uid})
          {:error, _} -> json(conn, 404, %{error: "not_found"})
        end
    end
  end