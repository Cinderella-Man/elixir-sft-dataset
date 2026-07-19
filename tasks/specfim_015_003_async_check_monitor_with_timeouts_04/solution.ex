  @spec status(GenServer.server(), service_name()) ::
          {:ok, status_info()} | {:error, :not_found}