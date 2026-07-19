  @spec with_own_invitation(
          Plug.Conn.t(),
          TeamStore.server(),
          String.t(),
          String.t(),
          (-> Plug.Conn.t())
        ) :: Plug.Conn.t()