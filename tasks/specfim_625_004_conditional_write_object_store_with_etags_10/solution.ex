  @spec do_put_object(
          state(),
          bucket(),
          %{optional(key()) => object()},
          key(),
          binary(),
          keyword()
        ) :: {:reply, {:ok, etag()} | {:error, :precondition_failed}, state()}