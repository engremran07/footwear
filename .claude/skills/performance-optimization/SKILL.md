---
name: performance-optimization
description: "Use when: reducing widget rebuilds, optimizing Firestore listener counts, fixing jank, reducing memory leaks, profiling APK size, optimizing list performance."
---

# Skill: Flutter & Firestore Performance Optimization

## Widget Rebuild Reduction

### Problem: Entire screen rebuilds on unrelated state changes
```dart
// BAD — entire screen rebuilds when ANY provider changes
class MyScreen extends ConsumerWidget {
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authUserProvider);
    final products = ref.watch(productsProvider);
    final stats = ref.watch(dashboardStatsProvider);
    // All three trigger a full rebuild when any one changes
  }
}

// GOOD — extract widgets that only watch what they need
class _ProductCount extends ConsumerWidget {
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(productsProvider).when(
      data: (p) => Text('${p.length}'),
      loading: () => const ShimmerLine(),
      error: (_, __) => const Text('—'),
    );
  }
}
```

### Problem: `ref.watch` in callbacks
```dart
// BAD — calling ref.watch inside onPressed
ElevatedButton(
  onPressed: () {
    final user = ref.watch(authUserProvider); // wrong! use ref.read in callbacks
  },
)

// GOOD
ElevatedButton(
  onPressed: () {
    final user = ref.read(authUserProvider).valueOrNull;
  },
)
```

## ListView Optimization
```dart
// ALWAYS use ListView.builder for lists > 20 items
ListView.builder(
  itemCount: items.length,
  itemBuilder: (context, i) => _ItemTile(item: items[i]),
  // Add itemExtent when items have fixed height (skip layout measurement)
  itemExtent: 72.0,
)

// For very large lists (100+), use sliver_list with RepaintBoundary
SliverList(
  delegate: SliverChildBuilderDelegate(
    (ctx, i) => RepaintBoundary(child: _ItemTile(item: items[i])),
    childCount: items.length,
  ),
)
```

## Firestore Stream Listener Optimization

### Count Active Listeners
Each `StreamProvider` = one Firestore listener (one TCP connection + server process)
Too many listeners = higher Firebase billing + memory pressure

```
Current listeners in ShoesERP app:
- authUserProvider (1)
- routesProvider OR routesBySellerProvider (1)
- shopsProvider OR shopsByRouteProvider (1)
- productsProvider (1)
- allVariantsProvider (1)
- allTransactionsProvider (1)
- sellerInventoryProvider (1)
- settingsProvider (1)
- roleAwareInvoicesProvider (1)
Total on dashboard: ~9 concurrent Firestore listeners

WARNING: Opening detail screens adds MORE listeners (detail providers).
On low-end devices, 15+ concurrent Firestore listeners can cause:
- High memory usage
- Slow snapshot processing
- Battery drain
```

### Listener Count Reduction Strategies
```dart
// 1. Use autoDispose on providers that aren't always needed
final transactionsByShopProvider = StreamProvider.autoDispose.family<...>((ref, shopId) {
  // Automatically cancels when no widget watches it
});

// 2. Limit detail providers to when actually needed (not in dashboard)
// Don't pre-load detail providers in dashboard provider if not shown

// 3. Use .limit() aggressively
.collection(Collections.invoices)
.orderBy('created_at', descending: true)
.limit(50)  // Don't load 200 unless user scrolls/paginates
```

## Image Loading Optimization
```dart
// cached_network_image — already in use ✅
// Always set cacheWidth/cacheHeight to prevent large image decoding
CachedNetworkImage(
  imageUrl: product.imageUrl,
  width: 80,
  height: 80,
  memCacheWidth: 80,   // decode at display size, not original size
  memCacheHeight: 80,
  fit: BoxFit.cover,
  errorWidget: (_, __, ___) => const Icon(Icons.broken_image),
)
```

## APK Size Optimization
```groovy
// android/app/build.gradle.kts
android {
  buildTypes {
    release {
      isShrinkResources = true   // remove unused resources
      isMinifyEnabled = true     // ProGuard/R8
    }
  }
  // Split per ABI (already done) ✅
  // Reduces APK from ~45MB to ~15MB per ABI
}
```

## Memory Leak Detection
Common Flutter memory leaks:
```dart
// LEAK: StreamSubscription not cancelled
class _MyState extends State<MyWidget> {
  late StreamSubscription _sub;
  
  @override
  void initState() {
    super.initState();
    _sub = someStream.listen((_) {}); // LEAK if not cancelled
  }
  
  @override
  void dispose() {
    _sub.cancel(); // FIX: cancel in dispose
    super.dispose();
  }
}

// LEAK: TextEditingController not disposed
class _FormState extends State<FormWidget> {
  final _nameC = TextEditingController();
  
  @override
  void dispose() {
    _nameC.dispose(); // MUST call dispose
    super.dispose();
  }
}

// In ShoesERP: All form screens verified to dispose controllers ✅
```

## Dashboard Performance Patterns
```dart
// CURRENT: derived from streams (zero extra Firestore reads) ✅
// dashboardStatsProvider derives from already-loaded streams

// WARNING: Calling ref.invalidate in RefreshIndicator triggers FULL reload
// of all providers — can cause 9 simultaneous Firestore requests
// Better: use debounce or reload individual providers
onRefresh: () async {
  // Only invalidate the data actually stale, not everything
  ref.invalidate(dashboardStatsProvider);
  await Future.delayed(const Duration(milliseconds: 500));
},
```

## Main Thread Offloading
Heavy operations should NOT run on the main isolate:
- ✅ PDF generation: `Isolate.run()` already used
- ✅ Excel export: verify uses `compute()` or `Isolate.run()`
- ⚠️ Large list sorting (100+ items): move to `compute()`

## Animation Performance
```dart
// GOOD: flutter_animate handles animation efficiently
widget.animate().fadeIn(duration: 300.ms).slideX(begin: 0.1)

// BAD: setState inside animation frames
AnimationController.addListener(() => setState(() {})); // causes every frame to rebuild
// Use AnimatedBuilder or AnimationBuilder instead
```

## Render Performance (60fps target)
- Use `const` constructors wherever possible
- Extract `const` widgets from `build()` to prevent recreation
- Use `RepaintBoundary` around complex list items
- Profile with `flutter run --profile` before every release

## Profiling Commands
```bash
# Profile mode (release performance, debug info)
flutter run --profile

# In DevTools: CPU profiler, memory profiler, widget inspector
flutter pub global activate devtools
flutter pub global run devtools
```
