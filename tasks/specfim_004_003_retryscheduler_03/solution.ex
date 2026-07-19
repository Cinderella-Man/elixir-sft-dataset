  @spec schedule(
          GenServer.server(),
          term(),
          NaiveDateTime.t(),
          {module(), atom(), list()},
          keyword()
        ) ::
          :ok | {:error, :already_exists | :invalid_opts}