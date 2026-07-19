  @spec push(GenServer.server(), term(), number()) ::
          :ok | :warming_up | {:alert, :upward_shift | :downward_shift}