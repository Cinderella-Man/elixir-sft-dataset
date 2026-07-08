# The harness dispatches via Plug.Test straight to PaginatedListWeb.Router
# (no ConnCase), so the tier-B archetype can no longer be inferred from the
# harness — state it explicitly: the kit compile + Repo/migrations boot are
# still required.
%{
  archetype: :phoenix_conncase,
  prefix: "PaginatedList",
  web_prefix: "PaginatedListWeb",
  otp_app: :paginated_list,
  db: :sqlite
}
