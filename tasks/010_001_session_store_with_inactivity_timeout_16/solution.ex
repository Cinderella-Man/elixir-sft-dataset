  @doc """
  Creates a new session containing `session_data`.

  Returns `{:ok, session_id}`. The inactivity timer starts immediately.
  """
  @spec create(server(), session_data()) :: {:ok, session_id()}
  def create(server, session_data) do
    GenServer.call(server, {:create, session_data})
  end