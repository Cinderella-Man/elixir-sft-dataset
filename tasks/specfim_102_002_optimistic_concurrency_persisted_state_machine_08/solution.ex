  @spec do_transition(
          map(),
          String.t(),
          event(),
          non_neg_integer(),
          state_name(),
          non_neg_integer()
        ) :: {:reply, term(), map()}