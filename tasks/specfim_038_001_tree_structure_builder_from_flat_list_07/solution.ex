  @spec detect_cycle([id()], %{id() => [id()]}) ::
          :ok | {:error, {:cycle_detected, [id()]}}