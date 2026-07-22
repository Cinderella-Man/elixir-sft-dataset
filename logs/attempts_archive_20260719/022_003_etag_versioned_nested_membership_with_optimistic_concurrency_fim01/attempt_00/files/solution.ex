  defp apply_add(conn, store, team_id, user_id, expected_version) do
    case TeamStore.add_member_safe(store, team_id, user_id, expected_version) do
      {:ok, added, new_version} ->
        conn
        |> Plug.Conn.put_resp_header("etag", Integer.to_string(new_version))
        |> send_json(201, %{added: added, version: new_version})

      {:error, :stale} ->
        send_json(conn, 412, %{error: "precondition_failed"})

      {:error, :conflict} ->
        send_json(conn, 409, %{error: "conflict"})

      {:error, :not_found} ->
        send_json(conn, 404, %{error: "not_found"})
    end
  end