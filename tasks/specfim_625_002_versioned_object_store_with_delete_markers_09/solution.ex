  @spec list_versions(server(), String.t(), String.t()) ::
          {:ok, [version_summary()]} | {:error, :bucket_not_found}