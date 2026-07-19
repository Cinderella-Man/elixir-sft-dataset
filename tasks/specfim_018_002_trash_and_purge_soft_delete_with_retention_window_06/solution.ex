  @spec update_document(GenServer.server(), pos_integer(), map()) ::
          {:ok, t()} | {:error, errors() | :not_found}