defp read_user_id(conn) do
  {:ok, body, conn} = read_body(conn)

  case Jason.decode(body) do
    {:ok, %{"user_id" => user_id}} when is_binary(user_id) -> {:ok, user_id, conn}
    _ -> {:error, conn}
  end
end