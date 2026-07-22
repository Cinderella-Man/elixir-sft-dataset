  def add(%__MODULE__{} = filter, item) do
    if MapSet.member?(filter.items, item) do
      filter
    else
      [active | rest] = filter.slices

      active = %{
        active
        | bits: set_bits(active, item),
          count: active.count + 1
      }

      slices =
        if active.count >= active.capacity do
          index = length(filter.slices)
          fresh = make_slice(index, filter.capacity0, filter.p0)
          [fresh, active | rest]
        else
          [active | rest]
        end

      %{
        filter
        | slices: slices,
          count: filter.count + 1,
          items: MapSet.put(filter.items, item)
      }
    end
  end