  @doc """
  Immediately removes the session identified by `session_id`.

  Always returns `:ok`, even if the session did not exist.
  """
  @spec destroy(server(), session_id()) :: :ok
  def destroy(server, session_id) do
    GenServer.call(server, {:destroy, session_id})
  end