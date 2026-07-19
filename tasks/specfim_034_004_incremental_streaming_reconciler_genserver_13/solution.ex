  @spec take_pending(state(), :left | :right, key()) ::
          {:ok, stream_record(), state()} | :error