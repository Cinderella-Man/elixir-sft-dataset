  @spec get_document(GenServer.server(), pos_integer(), keyword()) ::
          {:ok, t()} | {:error, :not_found}