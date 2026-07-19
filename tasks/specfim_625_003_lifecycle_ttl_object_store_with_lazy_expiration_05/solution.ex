  @spec delete_bucket(server(), String.t()) ::
          :ok | {:error, :not_found | :not_empty}