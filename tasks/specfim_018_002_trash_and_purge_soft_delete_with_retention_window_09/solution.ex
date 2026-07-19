  @spec purge_document(GenServer.server(), pos_integer()) ::
          {:ok, t()} | {:error, :not_deleted | :not_found}