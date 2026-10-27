# Module: role_assignments

Creates role assignments from a map and refuses the shapes that break least privilege:

- a scope that is a subscription or a resource group (only a resource or sub-resource is accepted);
- the management roles Owner, Contributor and User Access Administrator.

Newly created service principals are assigned with their principal type and without the directory lookup, which avoids the "principal does not exist" delay the lesson warns about.

```hcl
module "role_assignments" {
  source = "../../modules/role_assignments"

  assignments = {
    app_reads_secrets = {
      principal_id = module.identity.principal_id
      role         = "Key Vault Secrets User"
      scope        = module.key_vault.id
    }
  }
}
```

| Output | Meaning |
|---|---|
| `assignments` | Map of key to `{ principal_id, role, scope }` |

Test: `tests/role_assignments.tftest.hcl` (accepts a container scope, refuses resource group, subscription and management roles).
