  defp collect(results, success_count, quorum, all_refs, deadline) do
    cond do
      success_count >= quorum ->
        {results, true}

      map_size(results) == MapSet.size(all_refs) ->
        {results, false}

      true ->
        remaining = deadline - System.monotonic_time(:millisecond)

        if remaining <= 0 do
          {results, false}
        else
          receive do
            {ref, reply} when is_reference(ref) ->
              if MapSet.member?(all_refs, ref) and not Map.has_key?(results, ref) do
                Process.demonitor(ref, [:flush])

                new_success =
                  case reply do
                    {:ok, _} -> success_count + 1
                    _ -> success_count
                  end

                collect(Map.put(results, ref, reply), new_success, quorum, all_refs, deadline)
              else
                collect(results, success_count, quorum, all_refs, deadline)
              end

            {:DOWN, ref, :process, _pid, reason} ->
              if MapSet.member?(all_refs, ref) and not Map.has_key?(results, ref) do
                collect(
                  Map.put(results, ref, {:error, reason}),
                  success_count,
                  quorum,
                  all_refs,
                  deadline
                )
              else
                collect(results, success_count, quorum, all_refs, deadline)
              end
          after
            remaining ->
              {results, false}
          end
        end
    end
  end