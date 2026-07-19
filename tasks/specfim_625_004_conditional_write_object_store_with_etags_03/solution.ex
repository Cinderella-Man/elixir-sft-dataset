  @spec create_bucket(GenServer.server(), bucket()) ::
          :ok | {:error, :already_exists | :invalid_name}