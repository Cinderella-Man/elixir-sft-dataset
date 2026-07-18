  @doc """
  Retrieves session data for `session_id`.

  Returns `{:ok, data}` and resets the inactivity timer, or
  `{:error, :not_found}` if the session is missing or has expired.
  """
  @spec get(server(), session_id()) :: {:ok, session_data()} | {:error, :not_found}
  def get(server, session_id) do
    GenServer.call(server, {:get, session_id})
  end