  @spec fetch_bucket(state(), bucket()) ::
          {:ok, %{optional(key()) => object()}} | {:error, :bucket_not_found}