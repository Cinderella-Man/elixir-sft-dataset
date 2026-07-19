  @spec do_delete_object(state(), bucket(), %{optional(key()) => object()}, key(), keyword()) ::
          {:reply, :ok | {:error, :precondition_failed}, state()}