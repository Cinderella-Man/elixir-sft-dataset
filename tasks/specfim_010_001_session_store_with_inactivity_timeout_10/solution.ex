  @spec fetch_live_session(
          %{session_id() => session()},
          session_id(),
          integer(),
          non_neg_integer()
        ) :: {:ok, session()} | :expired | :missing