  @spec put_object(server(), String.t(), String.t(), binary(), map()) ::
          {:ok, String.t()} | {:error, :bucket_not_found}