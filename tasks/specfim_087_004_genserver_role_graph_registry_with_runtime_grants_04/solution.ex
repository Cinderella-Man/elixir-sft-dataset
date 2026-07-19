  @spec add_inheritance(GenServer.server(), atom(), atom()) ::
          :ok | {:error, :unknown_role | :cycle}