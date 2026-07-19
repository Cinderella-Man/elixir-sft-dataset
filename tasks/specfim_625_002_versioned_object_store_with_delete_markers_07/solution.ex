  @spec get_object_version(server(), String.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, :bucket_not_found | :not_found}