  defp comparator("relevance", ord) do
    dir = if ord == "asc", do: :asc, else: :desc

    fn {pa, sa}, {pb, sb} ->
      cond do
        sa != sb -> if dir == :desc, do: sa > sb, else: sa < sb
        pa.name != pb.name -> pa.name < pb.name
        true -> pa.id <= pb.id
      end
    end
  end

  defp comparator("name", ord) do
    dir = if ord == "desc", do: :desc, else: :asc

    fn {pa, _}, {pb, _} ->
      cond do
        pa.name != pb.name -> if dir == :asc, do: pa.name < pb.name, else: pa.name > pb.name
        true -> pa.id <= pb.id
      end
    end
  end

  defp comparator("price", ord) do
    dir = if ord == "desc", do: :desc, else: :asc

    fn {pa, _}, {pb, _} ->
      cond do
        pa.price_cents != pb.price_cents ->
          ascending? = pa.price_cents < pb.price_cents
          if dir == :asc, do: ascending?, else: not ascending?

        true ->
          pa.id <= pb.id
      end
    end
  end