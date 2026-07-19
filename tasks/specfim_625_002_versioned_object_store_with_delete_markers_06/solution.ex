  @spec get_object(server(), String.t(), String.t()) ::
          {:ok, map()} | {:error, :bucket_not_found | :not_found}