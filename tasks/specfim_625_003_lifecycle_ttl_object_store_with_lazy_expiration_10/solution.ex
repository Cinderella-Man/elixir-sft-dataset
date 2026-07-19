  @spec set_ttl(server(), String.t(), String.t(), ttl()) ::
          :ok | {:error, :bucket_not_found | :not_found}