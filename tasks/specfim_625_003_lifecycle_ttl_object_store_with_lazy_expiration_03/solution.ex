  @spec create_bucket(server(), String.t()) ::
          :ok | {:error, :already_exists | :invalid_name}