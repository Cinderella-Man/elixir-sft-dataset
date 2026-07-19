  @spec update(server(), session_id(), session_data()) ::
          {:ok, session_data()} | {:error, :not_found}