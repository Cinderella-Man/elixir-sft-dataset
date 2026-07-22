  defp read_body_params(conn) do
    {:ok, body, conn} = read_body(conn)

    case Jason.decode(body) do
      {:ok, %{"user_id" => user_id} = params} when is_binary(user_id) ->
        role = Map.get(params, "role", "member")
        if role in @roles, do: {:ok, user_id, role, conn}, else: {:error, conn}

      _ ->
        {:error, conn}
    end
  end