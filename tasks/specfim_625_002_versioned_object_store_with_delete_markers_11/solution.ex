  @spec list_objects(server(), String.t()) ::
          {:ok, [map()]} | {:error, :bucket_not_found}