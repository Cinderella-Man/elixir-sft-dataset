  @spec run([item()], pos_integer(), (any() -> any())) :: [
          %{item: any(), priority: integer(), result: any(), worker_id: non_neg_integer()}
        ]