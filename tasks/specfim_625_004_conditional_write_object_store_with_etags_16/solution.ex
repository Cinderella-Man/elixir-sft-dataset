  @spec fetch_object(%{optional(key()) => object()}, key()) ::
          {:ok, object()} | {:error, :not_found}