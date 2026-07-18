  @doc "Looks up a user by bearer `token`, returning `{:ok, user_id}` or `:error`."
  @spec get_user_by_token(server(), String.t()) :: {:ok, term()} | :error
  def get_user_by_token(server, token), do: GenServer.call(server, {:get_user_by_token, token})