  @spec step(
          String.t(),
          map(),
          (term() -> term()),
          non_neg_integer(),
          non_neg_integer() | :infinity
        ) ::
          {:cont, map()} | {:halt, map()}