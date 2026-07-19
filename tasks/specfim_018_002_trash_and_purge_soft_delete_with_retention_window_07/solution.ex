  @spec soft_delete_document(GenServer.server(), pos_integer()) ::
          {:ok, t()} | {:error, :not_found}