  defp on_cycle?(x, parent_of) do
    follow(parent_of[x], parent_of, x, MapSet.new([x]))
  end