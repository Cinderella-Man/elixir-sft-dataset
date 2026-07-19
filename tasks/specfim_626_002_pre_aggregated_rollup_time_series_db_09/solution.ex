  @spec buckets_in_range(%{bucket_start() => acc()}, integer(), integer()) ::
          [{bucket_start(), stats()}]