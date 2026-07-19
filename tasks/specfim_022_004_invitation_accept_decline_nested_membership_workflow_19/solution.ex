  @spec with_team_and_member(
          Plug.Conn.t(),
          TeamStore.server(),
          String.t(),
          (-> Plug.Conn.t())
        ) :: Plug.Conn.t()