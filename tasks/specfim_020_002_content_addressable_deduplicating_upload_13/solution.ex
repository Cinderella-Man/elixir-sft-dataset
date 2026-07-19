  @spec store_and_persist(
          Plug.Conn.t(),
          Plug.Upload.t(),
          non_neg_integer(),
          GenServer.server(),
          Path.t(),
          String.t()
        ) :: Plug.Conn.t()