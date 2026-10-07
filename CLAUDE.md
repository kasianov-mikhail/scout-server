# Maintaining these instructions

- When you notice recurring feedback or a new convention that isn't captured yet, proactively propose adding it as a rule — surface it as a suggested edit for the user to approve rather than editing on your own initiative. General Swift style, code organization and structure rules go to the shared user-level rule `~/.claude/rules/swift-style.md` (loaded automatically for Swift files in scout, scout-db, scout-server and scout-ip); only scout-server-specific conventions go here.

# Scout client contract

scout-server and the scout client app (`kasianov-mikhail/scout`) share an HTTP wire-format contract, so changes to the two repos are often interrelated: a change to request/response shapes, field names, the queryable-field set, or endpoints here (the `Wire` types, the controllers, and `API.md`) usually needs a matching change in scout's `Core/Database/Backend` layer (`HTTPQueryCoding`/`HTTPRecordCoding`/`HTTPDatabase`), and vice versa. They are separate repos, so a contract change normally ships as a PR in each — link the matching PR in the other repo from both descriptions. scout's `ServerContractTests` boots this server and runs against it (via scout's `Server` workflow), so a wire-format change here can break scout's CI — keep `API.md` and that test in sync.

# Initializer assignments

- In an initializer, if at least one property assignment needs `self.` (a parameter or local shadows the property), prefix every property assignment with `self.` for consistency; if none needs it, omit `self.` from all of them.
