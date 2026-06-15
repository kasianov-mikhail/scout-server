# Maintaining these instructions

When you notice recurring feedback or a new project convention that isn't captured here yet, proactively propose adding it as a rule to this file — surface it as a suggested edit for the user to approve rather than editing on your own initiative.

# Scout client contract

scout-server and the scout client app (`kasianov-mikhail/scout`) share an HTTP wire-format contract, so changes to the two repos are often interrelated: a change to request/response shapes, field names, the queryable-field set, or endpoints here (the `Wire` types, the controllers, and `API.md`) usually needs a matching change in scout's `Core/Database/Backend` layer (`HTTPQueryCoding`/`HTTPRecordCoding`/`HTTPDatabase`), and vice versa. They are separate repos, so a contract change normally ships as a PR in each — call out the companion PR in both descriptions. scout's `ServerContractTests` boots this server and runs against it (via scout's `Server` workflow), so a wire-format change here can break scout's CI — keep `API.md` and that test in sync.
