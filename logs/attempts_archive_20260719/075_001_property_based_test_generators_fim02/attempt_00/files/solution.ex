  def one_of_weighted(weighted_list) when is_list(weighted_list) and weighted_list != [] do
    # Expand each {weight, gen} pair into `weight` copies of `gen`, then hand
    # off to `StreamData.one_of/1` for uniform selection. This keeps the
    # implementation a single pipeline with no custom sampling math, and
    # correctly propagates shrinking through the underlying generators.
    expanded =
      Enum.flat_map(weighted_list, fn {weight, gen}
          when is_integer(weight) and weight >= 0 ->
        # weight 0 → List.duplicate returns [] → generator is never selected
        List.duplicate(gen, weight)
      end)

    SD.one_of(expanded)
  end