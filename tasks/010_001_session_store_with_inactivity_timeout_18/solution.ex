  @doc """
  Resets the inactivity timer for `session_id` without changing its data.

  Returns `:ok` on success or `{:error, :not_found}` if the session is
  missing or has expired.
  """
  @spec touch(server(), session_id()) :: :ok | {:error, :not_found}
  def touch(server, session_id) do
    GenServer.call(server, {:touch, session_id})
  end