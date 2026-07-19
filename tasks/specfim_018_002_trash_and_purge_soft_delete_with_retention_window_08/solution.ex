  @spec restore_document(GenServer.server(), pos_integer()) ::
          {:ok, t()} | {:error, :expired | :not_found}