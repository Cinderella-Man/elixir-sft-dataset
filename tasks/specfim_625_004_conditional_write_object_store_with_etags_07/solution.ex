  @spec delete_object(GenServer.server(), bucket(), key(), keyword()) ::
          :ok | {:error, :bucket_not_found | :precondition_failed}