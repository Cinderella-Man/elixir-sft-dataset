  @spec query_range(server(), String.t(), labels(), range(), function_kind(), pos_integer()) ::
          [{labels(), [{integer(), number()}]}]