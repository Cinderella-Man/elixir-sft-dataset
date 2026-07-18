  defp update_unique_tags(acc, tags) do
    Map.update!(acc, :unique_tags, fn ut ->
      Enum.reduce(tags, ut, fn {k, v}, tag_acc ->
        Map.update(tag_acc, k, MapSet.new([v]), &MapSet.put(&1, v))
      end)
    end)
  end