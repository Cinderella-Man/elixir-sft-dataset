  @spec merge_states(lww_state(), lww_state()) :: lww_state()
  defp merge_states(%{adds: la, removes: lr}, %{adds: ra, removes: rr}) do
    %{
      adds: merge_ts_maps(la, ra),
      removes: merge_ts_maps(lr, rr)
    }
  end