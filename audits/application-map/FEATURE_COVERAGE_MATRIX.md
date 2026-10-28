# Feature Coverage Matrix

## Scope note

This matrix maps the 32 registered route patterns using the current router,
role policy, collection constants, and existing screen register. It is
discovery and traceability evidence—not proof that every interaction or
role-specific path was executed. See
[screen-register.md](../../docs/frontend/screen-register.md) for screen-state
findings.

## Route and feature map

| Feature / route patterns | Roles and scope | Main Firestore paths | Representative tests | Status / documentation |
| --- | --- | --- | --- | --- |
| Login `/login`, `/bootstrap-profile` | Signed-out auth; signed-in profile recovery; concrete tenant required for business access | `users`, `tenants` | `app/test/widget/login_screen_feedback_test.dart`; auth refresh policy tests | Auth path source-reviewed; authenticated business acceptance not run. See `AGENTS.md` auth contract. |
| Dashboard `/` | Active tenant roles; selected support context for super-admin business metrics | `routes`, `customers`, `transactions`, `invoices`, `seller_inventory` | `app/test/widget/dashboard_startup_test.dart` | Startup test exists; live multi-role metrics not exercised in this audit. |
| Routes `/routes`, `/routes/new`, `/routes/:id`, `/routes/:id/edit` | Admin/tenant admin/supervisor operations; seller-scoped visibility; super-admin selected workspace | `routes`, `users`, `customers` | `app/test/widget/route_form_seller_load_test.dart`; `route_model_test.dart` | Router/source map; seller assignment restrictions remain Rules/provider-enforced. |
| Shops `/shops`, `/shops/new`, `/shops/:id`, `/shops/:id/edit` | Tenant roles; sellers constrained to assigned routes | `customers` (`Collections.shops`), `routes`, `transactions`, `invoices` | `shops_currency_filter_test.dart`; shop model tests | Currency/filter regressions exist; authenticated CRUD flow not run here. |
| Products `/products`, `/products/new`, `/products/:id`, `/products/:id/edit`, `/products/:id/variants/new`, `/products/:id/variants/:vid/edit` | Read for operational roles; writes restricted by capability and provider guards | `products`, `product_variants`, `seller_inventory` | `product_form_screen_test.dart`; product and variant model tests | Source and focused tests inventoried; full product workflow not re-executed in this audit. |
| Inventory `/inventory` | Admin/supervisor operational writes; sellers read own allocated stock; sale deductions linked to invoices | `seller_inventory`, `inventory_transactions`, `product_variants` | `inventory_screen_test.dart`; inventory model tests | UI states covered in existing tests; no production stock mutation or cross-device acceptance. |
| Invoice list/detail `/invoices`, `/invoices/:id` | Tenant-scoped read; role-specific actions | `invoices`, `customers`, `transactions` | `invoice_list_summary_test.dart`; invoice model tests | Read/summary tests exist; Rules Emulator covers tenant isolation. |
| Invoice create `/invoices/new` | Admin/tenant admin/supervisor may create sale/receipt within tenant; seller route-scoped; settlement/void/correction remain restricted | `invoices`, `transactions`, `customers`, `settings`, `seller_inventory`, `product_variants` | `create_sale_invoice_guard_test.dart`; `create_invoice_auth_state_test.dart`; Rules Emulator | Local Rules suite `180 passing`; production Rules undeployed. See `SESSION_LOG.md`. |
| Users `/users` | Local admin manages sellers; tenant admin manages permitted seller/supervisor roles; reserved platform role path | `users`, `routes`, `tenants` | `user_route_options_test.dart`; `users_list_workspace_context_test.dart`; `user_model_test.dart` | Role and retry tests exist; no authenticated user-management session exercised here. |
| Workspaces `/tenants` | Platform super-admin; metadata globally, business data only in selected reasoned workspace context | `tenants`, `users`, `platform_access_logs` | `tenant_management_error_test.dart`; tenant model/scope tests; Rules tests | Selected-workspace start linkage fixed locally; deployment pending. |
| History `/history` | Role-scoped tenant or assigned-route visibility | `transactions`, `invoices`, `customers`, `users` | Transaction/business-logic tests | Route/source map only; full interaction coverage not verified. |
| Notifications `/notifications` | Admin, tenant admin, supervisor; sellers denied | `notifications`, `customers`, `users` | `notification_center_feedback_test.dart`; `notification_visibility_test.dart`; Rules tests | Tenant-keyed providers and mark-read feedback have regression tests; production behavior not redeployed. |
| Reports `/reports` | Admin, tenant admin, supervisor; seller blocked by current policy | `transactions`, `invoices`, `customers`, `routes`, `users` | `pdf_and_excel_export_integration_test.dart`; `pdf_export_test.dart`; localization tests | Data/layout tests exist; full rendered format/role acceptance is partial. |
| Profile `/profile` and About `/about` | Active signed-in profile; owner-controlled credential workflows | `users` | Profile/auth tests in app/test | Source route mapped; not exhaustively interacted in this audit. |
| Settings `/settings`, `/settings/invoice-header` | Tenant admin/admin within workspace; super-admin platform hub versus selected workspace descendants | `settings`, `tenants`, `platform_access_logs` | Settings/header widget tests | Workspace context checks source-reviewed; production Rules not deployed for latest audit change. |
| Backup `/settings/backup` | Tenant admin/admin; route-scoped seller archive/restore; supervisor denied; super-admin selected workspace | `settings`, `users`, `routes`, `customers`, `transactions`, `invoices`, `products`, `product_variants`, `seller_inventory` | `database_backup_screen_test.dart`; backup scope/destination/cipher tests; `app_router_backup_access_test.dart` | Encrypted scoped workflow exists; test inventory only; no cloud restore run. |
| Data maintenance `/settings/flush` | Capability reserved to platform super-admin; current provider deliberately throws unsupported | No writes are supported | `database_flush_provider_test.dart`; `database_flush_screen_state_test.dart`; maintenance script Node tests | FAIL-CLOSED; feature resets not implemented pending approved integrity/recovery design. |
| Shared app shell/navigation | Route guards plus `PermissionPolicy`; UI visibility is not the security boundary | No direct writes | Router/backup access tests | 32 route patterns listed in app router; comprehensive dialog/menu inventory remains incomplete. |
| Financial PDF/XLSX/print/share | Same tenant/role scope as source report; PDF builder and locale pair govern presentation | Source feature collections; settings/header/logo | `pdf_export_test.dart`; `pdf_and_excel_export_integration_test.dart`; `financial_document_localization_test.dart` | Font/resource tests exist; complete current-source visual acceptance is partial; Urdu Nastaliq unsupported by current renderer. |

## Canonical collection names

The collection source is
[collections.dart](../../app/lib/core/constants/collections.dart). It
defines 15 constants representing 14 unique paths; `Collections.shops` aliases
the legacy Firestore path `customers`. No feature coverage row authorizes
direct screen writes.

## Coverage gaps

- This matrix does not enumerate every provider method, every dialog action,
  every test case, or every Firestore match block.
- CI currently runs Rules Emulator tests and targeted hygiene checks; it does
  not constitute an all-role authenticated integration suite.
- Dynamic role/feature configuration and workspace-admin reset operations are
  not implemented.
