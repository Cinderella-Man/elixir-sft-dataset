  # Rebuild an allowed <a> tag, keeping only a safe `href` attribute.
  # Returns `{iodata, new_poisoned_a}`.
  defp rebuild_tag("a", attrs_raw, self_closing?, pa) do
    case extract_href(attrs_raw) do
      nil ->
        # No href — emit a clean anchor with no attributes.
        tag = if self_closing?, do: "<a/>", else: "<a>"
        {tag, pa}

      href_val ->
        if javascript_href?(href_val) do
          # Poisoned anchor: emit nothing for the opening tag and remember to
          # drop the matching </a> as well.
          {"", true}
        else
          escaped = html_escape_attr(href_val)

          tag =
            if self_closing? do
              "<a href=\"" <> escaped <> "\"/>"
            else
              "<a href=\"" <> escaped <> "\">"
            end

          {tag, pa}
        end
    end
  end

  # Any other allowed tag: drop all attributes, emit just the bare tag.
  defp rebuild_tag(name, _attrs_raw, self_closing?, pa) do
    tag = if self_closing?, do: "<" <> name <> "/>", else: "<" <> name <> ">"
    {tag, pa}
  end