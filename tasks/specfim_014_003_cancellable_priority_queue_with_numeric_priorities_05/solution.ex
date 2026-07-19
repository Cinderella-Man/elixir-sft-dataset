  @spec status(server()) :: %{
          pending: non_neg_integer(),
          by_priority: %{non_neg_integer() => non_neg_integer()},
          cancelled: non_neg_integer()
        }