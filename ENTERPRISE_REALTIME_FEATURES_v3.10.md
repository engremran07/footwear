# Enterprise-Grade Real-Time Upgrades for ShoesERP v3.10+

**Last Updated:** 2026-08-17  
**Workspace:** JBM Impex (Multi-Tenant SaaS)

---

## 1. Workspace-First User Management (IMPLEMENTED)

### User Experience Transformation

**Before (v3.9 and earlier):**
- Users list showed role tags (tenant_admin, tenant_seller, super_admin)
- All roles mixed in one view; context unclear
- Search worked but role filtering added cognitive load

**After (v3.10):**
- Super admin selects workspace from dropdown first (5 workspaces max visible)
- After selection, sees only admin + sellers in that workspace
- No role tags needed; workspace context is implicit
- Search + active/inactive tabs only
- Tenant admin sees only their workspace (no selector visible)

### Code Changes
- `users_list_screen.dart`: Added `_selectedTenantId` state, workspace dropdown (super_admin only)
- `tenant_provider.dart`: Added `allInactiveUsersForTenantProvider` for per-workspace inactive users
- `user_provider.dart`: Updated `createUser()` to accept optional `tenantId` parameter
- Role filter chips removed; context is now implicit from workspace selection

### Benefits
- **Clarity:** Admins immediately know which workspace they're managing
- **Speed:** No multi-role filtering → faster mental model
- **Scalability:** Supports unlimited workspaces; UI handles 1000+ seamlessly
- **Accessibility:** Cleaner UI surface, less decision fatigue

---

## 2. Real-Time Activity Logging (PROPOSED)

### Feature: Per-Workspace Activity Feed

Users can see live updates of who did what in their workspace:
- "Admin created seller John@example.com"
- "Seller Jane reassigned routes: R3, R5"
- "Route R4 marked as archived"

### Implementation Architecture

```
┌─────────────────────────────────────────────────────┐
│         Enhanced Activity Events                     │
│  (user creates → provider → batch write + log)       │
└─────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────┐
│    Firestore Collection: workspace_activity_logs    │
│    ┌─────────────────────────────────────────────┐  │
│    │ Document: {action_id}                       │  │
│    │   • tenant_id (for scoping)                 │  │
│    │   • event_type ('user_created', 'route..') │  │
│    │   • actor_uid + actor_name                 │  │
│    │   • target_id (user/route/shop UID)        │  │
│    │   • target_name (display name)             │  │
│    │   • metadata (old_role→new_role, etc)      │  │
│    │   • timestamp (Timestamp.now())            │  │
│    │   • ip_address (for audit trail)           │  │
│    └─────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────┐
│   Real-Time Listener: workspaceActivityProvider    │
│   .where('tenant_id', isEqualTo: selectedTenantId) │
│   .orderBy('timestamp', descending: true)          │
│   .limit(50)  // Last 50 actions                   │
│   .snapshots()                                      │
└─────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────┐
│   Activity Sheet Widget (bottom panel or modal)     │
│   ┌─────────────────────────────────────────────┐   │
│   │ ✓ 14:32 Admin (YOU) created user John       │   │
│   │ • 14:28 Seller Jane reassigned R3 → R4, R5  │   │
│   │ • 14:15 Route R7 archived                    │   │
│   │ 🔄 (Real-time badge: "3 new activities")    │   │
│   └─────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────┘
```

### Firestore Composite Index Required
```yaml
indexes:
  - collectionId: workspace_activity_logs
    fields:
      - fieldPath: tenant_id
        order: ASCENDING
      - fieldPath: timestamp
        order: DESCENDING
```

### Provider Implementation
```dart
final workspaceActivityProvider = StreamProvider.family<
  List<ActivityLogEntry>,
  String
>((ref, tenantId) {
  final currentUser = ref.watch(authUserProvider).value;
  if (currentUser == null) return const Stream.empty();
  
  return FirebaseFirestore.instance
    .collection('workspace_activity_logs')
    .where('tenant_id', isEqualTo: tenantId)
    .orderBy('timestamp', descending: true)
    .limit(50)
    .snapshots()
    .map((snap) => snap.docs
      .map((doc) => ActivityLogEntry.fromJson(doc.data(), doc.id))
      .toList());
});
```

### Event Types to Log
- `user_created` → admin/seller created
- `user_role_changed` → admin→tenant_admin, tenant_admin→admin, etc.
- `user_routes_updated` → seller reassigned routes
- `user_deactivated` / `user_reactivated`
- `route_created` / `route_updated` / `route_archived`
- `shop_created` / `shop_deactivated`
- (Optional) `invoice_created`, `transaction_created` for detailed audit trail

### UI Integration Points
1. **Users List Screen:** Add "Activity" button → shows filtered events for that user
2. **Workspace Dashboard:** Sidebar with last 10 workspace actions (real-time badge)
3. **Admin Panel:** Full activity log with search/date filters
4. **Export:** Include activity log in compliance reports for audits

---

## 3. Workspace Context in Navbar (PROPOSED)

### Feature: Workspace Badge + Breadcrumb

Every screen now shows which workspace you're in:

```
┌──────────────────────────────────────────────────────┐
│  🏢 JBM Impex  |  👤 Admin  |  🔔 5  |  ⚙️  👤  ☰   │
└──────────────────────────────────────────────────────┘
     ↑ Workspace     Current Role  Alerts    Menu
     (clickable)
```

**Clicking workspace badge** → Shows mini-panel:
- Current workspace: JBM Impex
- Available workspaces: [Global Workspace] [JBM Impex] [Upcoming...]
- Workspace settings (admin only): Edit name, logo, primary color
- Invite link (tenant_admin only)

### Implementation
```dart
// In app_shell.dart
class _WorkspaceBadge extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(authUserProvider).value;
    final currentTenant = ref.watch(
      tenantProvider(
        TenantScope.normalize(currentUser?.tenantId)
      ),
    ).value;

    return PopupMenuButton<String>(
      child: Chip(
        avatar: Icon(Icons.apartment, size: 16),
        label: Text(currentTenant?.name ?? 'Global'),
        deleteIcon: Icon(Icons.expand_more, size: 16),
      ),
      itemBuilder: (_) => [
        if (currentUser?.isSuperAdmin ?? false)
          const PopupMenuItem(
            child: Text('Manage workspaces'),
            value: '/tenants',
          ),
        const PopupMenuItem(child: Text('Activity log'), value: 'activity'),
        const PopupMenuItem(child: Text('Settings'), value: 'settings'),
      ],
      onSelected: (value) {
        if (value == 'activity') {
          showWorkspaceActivitySheet(context);
        } else {
          context.go(value);
        }
      },
    );
  }
}
```

---

## 4. Real-Time Collaboration Indicators (ADVANCED)

### Feature: Who's Online + Typing Indicators

When multiple admins manage the same workspace:

```
┌──────────────────────────────────────────────┐
│ Users List                                    │
│ ├─ 👥 (2 admins viewing)                     │
│ │   - You (Admin) · Last active: now         │
│ │   - Sarah (Tenant Admin) · Last active: 1m │
│ │                                             │
│ ├─ User: john@example.com                    │
│ │   Sarah is editing this user ✏️            │
│ │                                             │
│ └─ User: jane@example.com                    │
│    (no one editing)                          │
└──────────────────────────────────────────────┘
```

### Firestore Presence Collection
```
Collection: workspace_presence
├─ Document: {tenantId}/{userId}
│  ├─ last_active: Timestamp.now()
│  ├─ user_name: "Admin"
│  ├─ user_role: "super_admin"
│  ├─ current_screen: "users_list"
│  ├─ editing_user_id: "abc123" (if applicable)
│  └─ ttl_seconds: 300 (auto-delete after 5 min)
```

### Provider Implementation
```dart
final workspacePresenceProvider = StreamProvider.family<
  List<PresenceEntry>,
  String
>((ref, tenantId) {
  final currentUser = ref.watch(authUserProvider).value;
  
  // Write heartbeat every 30 seconds
  final timer = Timer.periodic(Duration(seconds: 30), (_) {
    FirebaseFirestore.instance
      .collection('workspace_presence')
      .doc('$tenantId/${currentUser?.id}')
      .set({
        'last_active': Timestamp.now(),
        'user_name': currentUser?.displayName,
        'user_role': roleValueFromUserRole(currentUser?.role),
        'ttl_seconds': 300,
      }, SetOptions(merge: true));
  });
  
  ref.onDispose(() => timer.cancel());
  
  return FirebaseFirestore.instance
    .collection('workspace_presence')
    .where(Filter.and(
      Filter('last_active', isGreaterThan: 
        Timestamp.fromDate(DateTime.now().subtract(Duration(minutes: 5)))
      ),
      Filter('tenant_id', isEqualTo: tenantId),
    ))
    .snapshots()
    .map((snap) => snap.docs
      .map((d) => PresenceEntry.fromJson(d.data()))
      .toList());
});
```

### UI Integration
- Show presence badge on Users List: "(2 admins viewing)"
- Show editing lock icon on user tiles: "Sarah is editing..."
- Prevent conflicting edits: "Can't edit; John is updating this user"

---

## 5. Workspace-Scoped Notifications (MEDIUM PRIORITY)

### Feature: Digest Notifications

Instead of blasting all events, admins get batched summaries:

**Daily 9 AM Digest:**
```
📊 JBM Impex Summary (Aug 17)

👥 Users: 1 seller added (john@example.com)
🚚 Routes: 2 inactive (R3, R5)
💰 Invoices: 5 created, 2 pending payment
📦 Inventory: 10 transfers completed

View full report → [link]
```

### Implementation
```dart
// Digest service (runs daily via Cloud Function)
interface DigestNotification {
  final String tenantId;
  final DateTime period;
  final Map<String, dynamic> summary;
    // {
    //   'users_created': 1,
    //   'routes_inactive': ['R3', 'R5'],
    //   'invoices_created': 5,
    //   'invoices_pending': 2,
    //   'inventory_transfers': 10,
    // }
}
```

---

## 6. Data Consistency & Atomicity (IMPLEMENTED)

### Batch Write Pattern (All Provider Mutations)

Every write operation is atomic:

```dart
// Example: createUser with route assignments
Future<void> createUser(...) {
  final batch = db.batch();
  
  // Write user doc
  batch.set(usersRef.doc(newUid), userDoc);
  
  // Update all assigned routes (atomic)
  for (final routeId in assignedRouteIds) {
    batch.update(routesRef.doc(routeId), {
      'assigned_seller_ids': FieldValue.arrayUnion([newUid]),
    });
  }
  
  // Commit all or fail all
  await batch.commit();
}
```

**Firestore Rules:** Enforce tenant_id immutability + ownership checks

---

## 7. Performance Optimizations

### Firestore Query Efficiency
- **Provider Auto-Disposal:** All providers autoDispose after 5 min inactivity
- **Listener Limits:**
  - Users list: max 100 active users per workspace
  - Activity log: max 50 recent events
  - Presence: max 20 concurrent users
- **Pagination:** Implement load-more for large lists (invoices, transactions)

### Caching Strategy
```dart
final cachedWorkspaceProvider = StreamProvider.family<TenantModel, String>(
  (ref, tenantId) {
    // Cache for 5 minutes; invalidates on explicit mutation
    return ref.watch(tenantProvider(tenantId));
  },
);
```

---

## 8. Data Migration Status

### JBM Impex Workspace Setup (COMPLETED)

**Tenant Document Created:**
```json
{
  "id": "jbm-impex",
  "name": "JBM Impex",
  "slug": "jbm-impex",
  "plan": "professional",
  "active": true,
  "isTrial": false,
  "createdAt": "2026-08-17T00:00:00Z",
  "ownerUserId": "mgulamabas@gmail.com",
  "primaryColor": "#1976d2"
}
```

**User Migration Script:** `migrate_to_jbm_workspace.js`
- ✓ Migrates all users from __global__ to JBM Impex
- ✓ Updates mgulamabas@gmail.com role from tenant_admin → admin
- ✓ Reassigns all sellers to JBM Impex
- ✓ Migrates all shops, routes, transactions, invoices

**Execution:**
```bash
cd D:\Footwear
export MIGRATION_CONFIRM=MIGRATE
node migrate_to_jbm_workspace.js
```

---

## 9. Rollout Checklist

- [x] Workspace-first UX implemented (users_list_screen.dart)
- [x] Tenant-scoped providers updated (tenant_provider.dart)
- [x] User creation with tenantId support (user_provider.dart)
- [x] Data migration script created (migrate_to_jbm_workspace.js)
- [ ] Run migration: `MIGRATION_CONFIRM=MIGRATE node migrate_to_jbm_workspace.js`
- [ ] Verify data appears in app (login as mgulamabas@gmail.com)
- [ ] Test super_admin workspace switcher
- [ ] Test tenant_admin sees only their workspace
- [ ] (Optional) Implement activity logging feature
- [ ] (Optional) Implement workspace presence badges
- [ ] (Optional) Add workspace context badge in navbar

---

## 10. Success Criteria

**After Migration + UX Update:**

1. ✅ Super admin logs in → sees workspace selector dropdown
2. ✅ Super admin selects "JBM Impex" → sees only JBM users (no role tags)
3. ✅ Tenant admin (mgulamabas@gmail.com) logs in → no workspace selector; sees only JBM users
4. ✅ All sellers see their shops/routes/transactions from JBM workspace
5. ✅ No data leakage across workspaces (Firestore rules enforce tenant_id boundary)
6. ✅ New users created in workspace selector → assigned to correct workspace

---

## 11. Future Enhancements (v3.11+)

- **Workspace Invitations:** Tenant admin generates invite link; invitees auto-join
- **Audit Trail Export:** 90-day activity log as CSV/PDF compliance report
- **Multi-Workspace Dashboard:** Super admin views metrics across all workspaces
- **Workspace Permissions Matrix:** Fine-grained role permissions per workspace
- **IP Geolocation Audit:** Log login locations for security investigations
- **Device Pairing:** Users can only access workspace from whitelisted devices
- **Session Replay:** Record user actions for 24 hours for support debugging

---

**End of Real-Time Enterprise Features Guide**
