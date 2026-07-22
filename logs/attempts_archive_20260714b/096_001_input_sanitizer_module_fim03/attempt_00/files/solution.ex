  defp rebuild_tag("a", attrs_raw, self_closing?, pa) do
    href = extract_href(attrs_raw)

    case href do
      nil ->
        # No href — emit a clean anchor tag
        {if(self_closing?, do: "<a/>", else: "<a>"), pa}

      href_val ->
        if javascript_href?(href_val) do
          # Poisoned: suppress opening tag, set poisoned state so the
          # closing tag is also suppressed when encountered.
          {"", true}
        else
          escaped = html_escape_attr(href_val)
          tag = if self_closing?, do: ~s(<a href="#{escaped}"/>), else: ~s(<a href="#{escaped}">)
          {tag, pa}
        end
    end
  end

  defp rebuild_tag(name, _attrs_raw, self_closing?, pa) do
    tag = if self_closing?, do: "<#{name}/>", else: "<#{name}>"
    {tag, pa}
  end