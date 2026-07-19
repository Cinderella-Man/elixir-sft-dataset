  @spec put_object(GenServer.server(), bucket(), key(), binary(), keyword()) ::
          {:ok, etag()} | {:error, :bucket_not_found | :precondition_failed}