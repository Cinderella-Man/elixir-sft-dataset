  @doc """
  Looks up a user by bearer token.

  Returns `{:ok, user_id}` when the token is known, otherwise `:error`.
  """
  @spec get_user_by_token(server(), String.t()) :: {:ok, String.t()} | :error
  def get_user_by_token(server, token) do
    GenServer.call(server, {:get_user_by_token, token})
  end