  @spec run(list(), pos_integer(), (any() -> any()), keyword()) :: %{
          results: [%{item: any(), result: any(), worker_id: non_neg_integer()}],
          metrics: %{
            processed: %{non_neg_integer() => non_neg_integer()},
            steals: %{non_neg_integer() => non_neg_integer()},
            stolen: %{non_neg_integer() => non_neg_integer()}
          }
        }