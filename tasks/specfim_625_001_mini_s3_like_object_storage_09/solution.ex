  @spec list_objects(GenServer.server(), String.t(), keyword()) ::
          {:ok, [map()]} | {:error, atom()}