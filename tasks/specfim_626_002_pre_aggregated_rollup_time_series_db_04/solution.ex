  @spec query(
          GenServer.server(),
          metric_name(),
          labels(),
          {integer(), integer()}
        ) :: [{labels(), [{bucket_start(), stats()}]}]