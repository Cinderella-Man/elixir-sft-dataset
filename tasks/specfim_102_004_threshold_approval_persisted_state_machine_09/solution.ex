  @spec persist(
          String.t(),
          event(),
          state_name(),
          state_name(),
          non_neg_integer(),
          map()
        ) :: {:reply, term(), map()}