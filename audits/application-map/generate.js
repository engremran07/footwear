const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const outputDir = __dirname;
const root = path.resolve(outputDir, '..', '..');
const generatedAt = new Date().toISOString();
const excluded = [
  '.git/**',
  '**/node_modules/**',
  '**/build/**',
  '**/.dart_tool/**',
  '**/coverage/**',
  '**/.gradle/**',
  'binary assets and generated lock/build metadata',
];
const limitations = [
  'This is static source discovery, not an execution trace or proof of production behavior.',
  'Dart relationships inferred from imports, identifiers, and nearby query text can over- or under-connect dynamic/reflection-driven behavior.',
  'Firestore Rules are indexed as source clauses; this generator does not evaluate Rules semantics, getAfter dependencies, or runtime access outcomes.',
  'A test declaration is not a passing test. Current-tree test status is not executed by this generator.',
  'Binary assets, build products, vendored dependencies, Git internals, and generated lockfiles are excluded.',
  'Authentication, live Firestore contents, Firebase deployment state, device behavior, and external provider configuration are not inspected.',
  'Screen actions are static callback-site candidates; closures, generated controls, and callbacks assembled from data may be missed.',
];

function read(relativePath) {
  try {
    return fs.readFileSync(path.join(root, relativePath), 'utf8').replace(/^\uFEFF/, '');
  } catch {
    return null;
  }
}

function walk(relativePath, accept) {
  const absolute = path.join(root, relativePath);
  if (!fs.existsSync(absolute)) return [];
  const result = [];
  for (const entry of fs.readdirSync(absolute, { withFileTypes: true })) {
    if (entry.name === 'node_modules' || entry.name === 'build' || entry.name === '.dart_tool' || entry.name === '.git' || entry.name === 'coverage' || entry.name === '.gradle') continue;
    const child = path.join(relativePath, entry.name).replaceAll(path.sep, '/');
    if (entry.isDirectory()) result.push(...walk(child, accept));
    else if (accept(child)) result.push(child);
  }
  return result;
}

function lineAt(text, offset) {
  return text.slice(0, offset).split('\n').length;
}

function evidence(file, line, confidence = 'direct', note = '') {
  return { path: file, line, confidence, note };
}

function featureFor(file, name = '') {
  const source = `${file} ${name}`.toLowerCase();
  if (/invoice|receipt|credit.?note|void|payment/.test(source)) return 'Invoices and finance';
  if (/inventory|seller.?stock|product.?provider|transfer/.test(source)) return 'Inventory and transfers';
  if (/transaction|ledger|shop.?detail|customer/.test(source)) return 'Shops and ledger';
  if (/tenant|workspace|device|session|auth|login|user.?provider/.test(source)) return 'Identity and workspaces';
  if (/report|pdf|excel|export|print|share/.test(source)) return 'Reports and exports';
  if (/setting|profile|theme|locale|l10n|notification/.test(source)) return 'Settings and experience';
  if (/route/.test(source)) return 'Routes and sellers';
  if (/dashboard|alert/.test(source)) return 'Dashboard and alerts';
  if (/backup|restore|flush/.test(source)) return 'Backup and recovery';
  if (/workflow|release|gradle|firebase/.test(source)) return 'Build and release';
  return 'Core platform';
}

const nodes = [];
const edges = [];
const nodeById = new Map();
const edgeById = new Set();
const sourceTexts = new Map();
const modules = new Map();
const providerNodesByName = new Map();
const modelNodesByName = new Map();
const collectionNodesByConstant = new Map();
const routeNodesByScreen = new Map();
const unresolved = [];

function addNode(category, name, file, line, details = {}, idOverride) {
  const id = idOverride || `${category}:${name}:${file}:${line}`;
  if (nodeById.has(id)) return nodeById.get(id);
  const node = {
    id,
    category,
    name,
    feature: featureFor(file, name),
    source: file ? evidence(file, line) : null,
    details,
    risk: [],
  };
  nodes.push(node);
  nodeById.set(id, node);
  return node;
}

function addEdge(from, to, type, ev, confidence = 'direct', label = '') {
  if (!nodeById.has(from) || !nodeById.has(to)) return;
  const key = `${from}|${to}|${type}|${ev?.path || ''}|${ev?.line || 0}`;
  if (edgeById.has(key)) return;
  edgeById.add(key);
  edges.push({ id: `edge:${edges.length + 1}`, from, to, type, label, confidence, evidence: ev ? [ev] : [] });
}

function sourceFiles(directory, suffixes) {
  return walk(directory, (file) => suffixes.some((suffix) => file.endsWith(suffix)));
}

const dartFiles = sourceFiles('app/lib', ['.dart']);
const appTestFiles = sourceFiles('app/test', ['.dart']);
const rulesTestFiles = sourceFiles('tests', ['.js', '.ts']);
const functionFiles = sourceFiles('functions/src', ['.js', '.ts', '.mjs', '.cjs']);
const workflowFiles = sourceFiles('.github/workflows', ['.yml', '.yaml']);
const toolFiles = sourceFiles('tool', ['.js', '.mjs', '.cjs', '.ps1', '.sh']);
const rootScripts = fs.readdirSync(root).filter((file) => /\.(?:js|mjs|cjs|ps1|sh)$/.test(file)).map((file) => file.replaceAll(path.sep, '/'));
const androidBuildFiles = sourceFiles('app/android', ['.gradle', '.kts', '.xml']);
const webShellFiles = sourceFiles('app/web', ['.html', '.json', '.js', '.css']);
const fastlaneFiles = walk('fastlane', (file) => /\.(?:rb|json|md)$/.test(file) || ['Appfile', 'Fastfile', 'Gemfile'].includes(path.basename(file)));
const functionManifests = ['functions/package.json', 'functions/tsconfig.json'].filter((file) => fs.existsSync(path.join(root, file)));
const documentationFiles = walk('.', (file) => file.endsWith('.md') || file.endsWith('.txt'))
  .filter((file) => !file.startsWith('audits/application-map/'));
const allScanned = [...new Set([
  ...dartFiles,
  ...appTestFiles,
  ...rulesTestFiles,
  ...functionFiles,
  ...workflowFiles,
  ...toolFiles,
  ...rootScripts,
  ...androidBuildFiles,
  ...webShellFiles,
  ...fastlaneFiles,
  ...functionManifests,
  'firestore.rules',
  'firestore.indexes.json',
  'firebase.json',
  'app/firebase.json',
  '.firebaserc',
  'app/pubspec.yaml',
  'package.json',
])].filter((file) => read(file) !== null);

for (const file of allScanned) sourceTexts.set(file, read(file));

for (const file of dartFiles) {
  const text = sourceTexts.get(file);
  const module = addNode('module', file, file, 1, { language: 'Dart', lines: text.split('\n').length }, `module:${file}`);
  modules.set(file, module);
}

const nonDartSourceFiles = [...appTestFiles, ...rulesTestFiles, ...functionFiles, ...workflowFiles, ...toolFiles, ...rootScripts, ...androidBuildFiles, ...webShellFiles, ...fastlaneFiles];
for (const file of nonDartSourceFiles) {
  if (modules.has(file)) continue;
  const text = sourceTexts.get(file) || '';
  const language = path.extname(file).replace('.', '') || 'extensionless';
  const module = addNode('module', file, file, 1, { language, lines: text.split('\n').length }, `module:${file}`);
  modules.set(file, module);
}

const userModel = sourceTexts.get('app/lib/models/user_model.dart') || '';
const roleMatch = userModel.match(/enum\s+UserRole\s*\{([\s\S]*?)\}/);
const roleValues = roleMatch
  ? [...roleMatch[1].matchAll(/\b([a-z][a-z0-9_]*)\b/g)].map((match) => match[1]).filter((value) => !['const', 'UserRole'].includes(value))
  : ['admin', 'manager', 'seller', 'tenant_admin', 'super_admin'];
const knownRoles = [...new Set([...roleValues, 'admin', 'manager', 'seller', 'tenant_admin', 'super_admin'])];
const roleNodes = new Map();
for (const role of knownRoles) {
  const roleFile = userModel.includes(role) ? 'app/lib/models/user_model.dart' : 'firestore.rules';
  const roleText = sourceTexts.get(roleFile) || read(roleFile) || '';
  const roleOffset = roleText.indexOf(role);
  const roleNode = addNode('role', role, roleFile, Math.max(1, lineAt(roleText, Math.max(0, roleOffset))), {
    evidenceAlso: ['firestore.rules', 'app/lib/core/utils/role_utils.dart'],
    confidence: 'source-token; verify role semantics in model and Rules',
  }, `role:${role}`);
  roleNodes.set(role, roleNode);
}

const collectionText = sourceTexts.get('app/lib/core/constants/collections.dart') || '';
const collectionConstants = new Map();
for (const match of collectionText.matchAll(/static\s+const\s+(\w+)\s*=\s*(?:'([^']+)'|"([^"]+)"|(\w+))\s*;/g)) {
  const constant = match[1];
  const rawValue = match[2] || match[3] || match[4];
  const value = collectionConstants.has(rawValue) ? collectionConstants.get(rawValue).name : rawValue;
  const node = addNode('collection', value, 'app/lib/core/constants/collections.dart', lineAt(collectionText, match.index), {
    constant,
    constants: [],
    aliases: [],
  }, `collection:${value}`);
  node.details.constants = [...new Set([...(node.details.constants || []), constant])];
  if (constant !== value) node.details.aliases = [...new Set([...(node.details.aliases || []), constant])];
  collectionNodesByConstant.set(constant, node);
  collectionConstants.set(constant, node);
}

const routeFile = 'app/lib/core/router/app_router.dart';
const routerText = sourceTexts.get(routeFile) || '';
const routeMatches = [...routerText.matchAll(/GoRoute\s*\(\s*path:\s*['"]([^'"]+)['"]/g)];
let lastAbsolutePath = '';
for (let index = 0; index < routeMatches.length; index++) {
  const match = routeMatches[index];
  const rawPath = match[1];
  if (rawPath.startsWith('/')) lastAbsolutePath = rawPath;
  const routePath = rawPath.startsWith('/') ? rawPath : `${lastAbsolutePath.replace(/\/$/, '')}/${rawPath}`;
  const end = routeMatches[index + 1]?.index ?? Math.min(routerText.length, match.index + 1800);
  const routeBlock = routerText.slice(match.index, end);
  const target = routeBlock.match(/_(?:fade|slide)Page\(\s*(?:const\s+)?([A-Z]\w+)/);
  const targetScreen = target?.[1] || null;
  const line = lineAt(routerText, match.index);
  const route = addNode('route', routePath, routeFile, line, {
    declaredPath: rawPath,
    targetScreen,
    guard: /security/.test(routePath) ? 'tenant security scope guard' : (/users|settings|reports|routes\/.*(?:new|edit)/.test(routePath) ? 'role guard candidate' : 'authenticated shell'),
  }, `route:${routePath}`);
  if (targetScreen) {
    const values = routeNodesByScreen.get(targetScreen) || [];
    values.push(route);
    routeNodesByScreen.set(targetScreen, values);
  } else {
    unresolved.push({ type: 'route-target', path: routePath, file: routeFile, line, note: 'Page builder target not statically resolved.' });
  }
}

const screenNodesByName = new Map();
for (const file of dartFiles.filter((file) => file.startsWith('app/lib/screens/'))) {
  const text = sourceTexts.get(file);
  for (const match of text.matchAll(/\bclass\s+([A-Z]\w+)\s+extends\s+(?:ConsumerWidget|ConsumerStatefulWidget|StatefulWidget|StatelessWidget|HookWidget)\b/g)) {
    const node = addNode('screen', match[1], file, lineAt(text, match.index), {
      widgetBase: match[0].match(/extends\s+(\w+)/)?.[1],
    }, `screen:${match[1]}`);
    screenNodesByName.set(match[1], node);
    const module = modules.get(file);
    addEdge(node.id, module.id, 'declared-in', evidence(file, lineAt(text, match.index)));
  }
}

const widgetNodesByName = new Map();
for (const file of dartFiles.filter((file) => file.startsWith('app/lib/widgets/'))) {
  const text = sourceTexts.get(file);
  for (const match of text.matchAll(/\bclass\s+([A-Z]\w+)\s+extends\s+(?:ConsumerWidget|ConsumerStatefulWidget|StatefulWidget|StatelessWidget|HookWidget)\b/g)) {
    const node = addNode('widget', match[1], file, lineAt(text, match.index), {
      widgetBase: match[0].match(/extends\s+(\w+)/)?.[1],
    }, `widget:${match[1]}`);
    widgetNodesByName.set(match[1], node);
    addEdge(node.id, modules.get(file).id, 'declared-in', evidence(file, lineAt(text, match.index)));
  }
}

for (const file of dartFiles.filter((file) => /app\/lib\/(?:core\/)?providers?\//.test(file) || file.startsWith('app/lib/providers/'))) {
  const text = sourceTexts.get(file);
  const providerRegex = /^\s*(?:final|late\s+final)\s+(\w+)\s*=\s*(StreamProvider|FutureProvider|Provider|NotifierProvider|AsyncNotifierProvider)\b/gm;
  for (const match of text.matchAll(providerRegex)) {
    const node = addNode('provider', match[1], file, lineAt(text, match.index), { providerType: match[2] }, `provider:${match[1]}`);
    providerNodesByName.set(match[1], node);
    addEdge(node.id, modules.get(file).id, 'declared-in', evidence(file, lineAt(text, match.index)));
  }
  for (const match of text.matchAll(/^\s*class\s+(\w+)\s+extends\s+(AsyncNotifier|Notifier|StreamNotifier|BuildlessAutoDisposeNotifier|BuildlessNotifier)\b/gm)) {
    const node = addNode('provider', match[1], file, lineAt(text, match.index), { providerType: match[2], declaration: 'notifier class' }, `provider-class:${match[1]}`);
    providerNodesByName.set(match[1], node);
    addEdge(node.id, modules.get(file).id, 'declared-in', evidence(file, lineAt(text, match.index)));
  }
}

for (const file of dartFiles.filter((file) => /app\/lib\/(?:core\/)?models\//.test(file) || file.startsWith('app/lib/models/'))) {
  const text = sourceTexts.get(file);
  for (const match of text.matchAll(/^\s*(?:abstract\s+)?class\s+([A-Z]\w+)/gm)) {
    const node = addNode('model', match[1], file, lineAt(text, match.index), {}, `model:${match[1]}`);
    modelNodesByName.set(match[1], node);
    addEdge(node.id, modules.get(file).id, 'declared-in', evidence(file, lineAt(text, match.index)));
  }
}

for (const file of dartFiles.filter((file) => file.startsWith('app/lib/core/services/'))) {
  const text = sourceTexts.get(file);
  for (const match of text.matchAll(/^\s*(?:abstract\s+)?class\s+([A-Z]\w+)/gm)) {
    const node = addNode('service', match[1], file, lineAt(text, match.index), {}, `service:${match[1]}`);
    addEdge(node.id, modules.get(file).id, 'declared-in', evidence(file, lineAt(text, match.index)));
  }
}

const componentNodes = [...screenNodesByName.values(), ...widgetNodesByName.values()];
for (const component of componentNodes) {
  const text = sourceTexts.get(component.source.path) || '';
  for (const [providerName, provider] of providerNodesByName) {
    const match = new RegExp(`\\b${providerName}\\b`).exec(text);
    if (match) addEdge(component.id, provider.id, 'uses-provider', evidence(component.source.path, lineAt(text, match.index), 'direct', 'Identifier reference in component source.'));
  }
  for (const [widgetName, widget] of widgetNodesByName) {
    if (widget.id === component.id) continue;
    const match = new RegExp(`\\b${widgetName}\\b`).exec(text);
    if (match) addEdge(component.id, widget.id, 'references-widget', evidence(component.source.path, lineAt(text, match.index), 'inferred', 'Widget type referenced in component file.'));
  }
  for (const [role, roleNode] of roleNodes) {
    const match = new RegExp(`\\b${role}\\b|\\bis${role.replace(/(^|_)([a-z])/g, (_, _sep, letter) => letter.toUpperCase())}\\b`).exec(text);
    if (match) addEdge(roleNode.id, component.id, 'role-gates-or-mentions', evidence(component.source.path, lineAt(text, match.index), 'inferred', 'Role token/helper occurs in component source; not a complete authorization proof.'));
  }
}

const moduleNodes = [...modules.values()];
for (const module of moduleNodes) {
  const file = module.source.path;
  const text = sourceTexts.get(file) || '';
  const collectionCall = /\.collection(?:Group)?\(\s*Collections\.(\w+)/g;
  for (const match of text.matchAll(collectionCall)) {
    const collection = collectionNodesByConstant.get(match[1]);
    if (collection) addEdge(module.id, collection.id, 'reads-or-writes-collection', evidence(file, lineAt(text, match.index), 'direct', 'Collection reference; direction depends on surrounding method.'));
    else unresolved.push({ type: 'collection-constant', name: match[1], file, line: lineAt(text, match.index), note: 'Referenced Collections constant was not parsed.' });
  }
  for (const [modelName, model] of modelNodesByName) {
    const match = new RegExp(`\\b${modelName}\\b`).exec(text);
    if (match && file !== model.source.path) addEdge(module.id, model.id, 'references-model', evidence(file, lineAt(text, match.index), 'inferred', 'Model identifier occurs in module source.'));
  }
  for (const [providerName, provider] of providerNodesByName) {
    const match = new RegExp(`\\b${providerName}\\b`).exec(text);
    if (match && file !== provider.source.path) addEdge(module.id, provider.id, 'references-provider', evidence(file, lineAt(text, match.index), 'inferred', 'Provider identifier occurs in module source.'));
  }
}

function declarationRegion(provider) {
  const text = sourceTexts.get(provider.source.path) || '';
  const declarations = [...text.matchAll(/^\s*(?:final|late\s+final|class)\s+\w+/gm)];
  const start = text.split('\n').slice(0, provider.source.line - 1).join('\n').length;
  const own = declarations.filter((item) => item.index <= start).at(-1);
  if (!own) return '';
  const next = declarations.find((item) => item.index > own.index);
  return text.slice(own.index, next?.index ?? text.length);
}

for (const [providerName, provider] of providerNodesByName) {
  const region = declarationRegion(provider);
  for (const [targetName, target] of providerNodesByName) {
    if (provider.id === target.id) continue;
    const escaped = targetName.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const match = new RegExp(`\\b${escaped}\\b`).exec(region);
    if (!match) continue;
    const regionText = sourceTexts.get(provider.source.path) || '';
    const offset = regionText.indexOf(region) + match.index;
    addEdge(provider.id, target.id, 'depends-on-provider', evidence(provider.source.path, lineAt(regionText, offset), 'inferred', 'Provider identifier occurs in its declaration region; recheck generated/family wrappers.'));
  }
}

const providerAdjacency = new Map([...providerNodesByName.values()].map((provider) => [provider.id, []]));
for (const edge of edges.filter((edge) => edge.type === 'depends-on-provider')) providerAdjacency.get(edge.from)?.push(edge.to);
let cycleIndex = 0;
const cycleStack = [];
const cycleOnStack = new Set();
const cycleIndexMap = new Map();
const cycleLowMap = new Map();
const providerCycles = [];
function visitProvider(nodeId) {
  cycleIndexMap.set(nodeId, cycleIndex);
  cycleLowMap.set(nodeId, cycleIndex++);
  cycleStack.push(nodeId);
  cycleOnStack.add(nodeId);
  for (const next of providerAdjacency.get(nodeId) || []) {
    if (!cycleIndexMap.has(next)) {
      visitProvider(next);
      cycleLowMap.set(nodeId, Math.min(cycleLowMap.get(nodeId), cycleLowMap.get(next)));
    } else if (cycleOnStack.has(next)) {
      cycleLowMap.set(nodeId, Math.min(cycleLowMap.get(nodeId), cycleIndexMap.get(next)));
    }
  }
  if (cycleLowMap.get(nodeId) === cycleIndexMap.get(nodeId)) {
    const component = [];
    let next;
    do {
      next = cycleStack.pop();
      cycleOnStack.delete(next);
      component.push(next);
    } while (next !== nodeId);
    if (component.length > 1 || (providerAdjacency.get(nodeId) || []).includes(nodeId)) providerCycles.push(component);
  }
}
for (const id of providerAdjacency.keys()) if (!cycleIndexMap.has(id)) visitProvider(id);

const recoveryNodes = [];
const recoveryPattern = /\bcatch\s*(?:\([^)]*\))?|\bonRetry\s*:|AppErrorMapper\.key|\bErrorState\b|\bretry\s*\(/g;
for (const file of dartFiles.filter((file) => file.startsWith('app/lib/screens/') || file.startsWith('app/lib/providers/') || file.startsWith('app/lib/core/services/'))) {
  const text = sourceTexts.get(file) || '';
  for (const match of text.matchAll(recoveryPattern)) {
    const line = lineAt(text, match.index);
    const node = addNode('recovery-path', match[0].replace(/\s+/g, ' ').trim(), file, line, {
      note: 'Error-catching, retry, or mapped-error marker; branch outcome must be inspected at this call site.',
    }, `recovery:${file}:${line}:${match[0].trim()}`);
    recoveryNodes.push(node);
    if (modules.has(file)) addEdge(modules.get(file).id, node.id, 'contains-recovery-path', evidence(file, line));
  }
}

for (const [screenName, routes] of routeNodesByScreen) {
  const screen = screenNodesByName.get(screenName);
  if (!screen) {
    for (const route of routes) unresolved.push({ type: 'missing-screen-symbol', path: route.name, file: route.source.path, line: route.source.line, note: `Route references ${screenName}, which was not found among screen widget classes.` });
    continue;
  }
  for (const route of routes) addEdge(route.id, screen.id, 'routes-to-screen', route.source);
}

const actionNodes = [];
const callbackPattern = /\b(onPressed|onTap|onLongPress|onChanged|onSelected|onSubmitted|onRefresh|onConfirm|onSelectionChanged|onApprove|onRevoke|onBlock|onReset)\s*:/g;
for (const file of dartFiles.filter((file) => file.startsWith('app/lib/screens/') || file.startsWith('app/lib/widgets/'))) {
  const text = sourceTexts.get(file) || '';
  for (const match of text.matchAll(callbackPattern)) {
    const line = lineAt(text, match.index);
    const before = text.slice(Math.max(0, match.index - 500), match.index);
    const after = text.slice(match.index, Math.min(text.length, match.index + 260));
    const labels = [
      ...[...before.matchAll(/\btr\(\s*['"]([^'"]+)['"]/g)].map((item) => ({ index: item.index, value: item[1] })),
      ...[...before.matchAll(/(?:tooltip|labelText)\s*:\s*(?:const\s+)?Text\(\s*['"]([^'"]+)['"]/g)].map((item) => ({ index: item.index, value: item[1] })),
    ].sort((left, right) => left.index - right.index);
    const handler = after.match(/(?:=>|\basync\s*\{?)[^\n]{0,100}/)?.[0] || '';
    const classMatch = [...text.slice(0, match.index).matchAll(/\bclass\s+([A-Za-z_]\w*)/g)].at(-1);
    const className = classMatch?.[1] || path.basename(file, '.dart');
    const labelKey = labels.at(-1)?.value;
    const actionName = labelKey ? `${match[1]} · ${labelKey}` : `${match[1]} in ${className}`;
    const node = addNode('action', actionName, file, line, {
      event: match[1],
      owner: className,
      labelKey: labelKey || null,
      handler: handler.trim(),
      feature: featureFor(file, actionName),
    }, `action:${file}:${line}:${match[1]}`);
    actionNodes.push(node);
    const owner = screenNodesByName.get(className) || widgetNodesByName.get(className);
    if (owner) addEdge(owner.id, node.id, 'exposes-action', evidence(file, line));
  }
}

const exportPattern = /\b(ExportSheet\.show|buildPdf\w*|generateInvoicePdf|generate\w*Pdf|exportTo\w*|SharePlus\.instance\.share|Printing\.layoutPdf)\s*\(/g;
const exportNodes = [];
for (const file of dartFiles) {
  const text = sourceTexts.get(file) || '';
  for (const match of text.matchAll(exportPattern)) {
    const line = lineAt(text, match.index);
    const node = addNode('export', match[1], file, line, { callSite: true }, `export:${file}:${line}:${match[1]}`);
    exportNodes.push(node);
    addEdge(modules.get(file).id, node.id, 'invokes-export', evidence(file, line));
  }
}

const backgroundPattern = /Timer\.periodic|AppLifecycleListener|addPostFrameCallback|Stream\.periodic|Isolate\.run|Future\.delayed|WidgetsBindingObserver|AppLifecycleState\./g;
const backgroundNodes = [];
for (const file of [...dartFiles, ...functionFiles, ...toolFiles]) {
  const text = sourceTexts.get(file) || read(file) || '';
  for (const match of text.matchAll(backgroundPattern)) {
    const line = lineAt(text, match.index);
    const module = modules.get(file);
    const node = addNode('background-task', match[0], file, line, { execution: 'static trigger or scheduling primitive; runtime frequency not measured' }, `background:${file}:${line}:${match[0]}`);
    backgroundNodes.push(node);
    if (module) addEdge(module.id, node.id, 'schedules-or-observes', evidence(file, line));
  }
}

const dependencyText = sourceTexts.get('app/pubspec.yaml') || '';
const currentVersion = dependencyText.match(/^version:\s*(\S+)/m)?.[1] || 'unknown';
const dependencyRegex = /^\s{2}([a-zA-Z0-9_]+):\s*(.*)$/gm;
for (const match of dependencyText.matchAll(dependencyRegex)) {
  if (['flutter', 'sdk', 'dev_dependencies', 'dependency_overrides', 'environment', 'uses-material-design', 'assets', 'fonts', 'family', 'asset'].includes(match[1])) continue;
  const line = lineAt(dependencyText, match.index);
  const node = addNode('integration', match[1], 'app/pubspec.yaml', line, { declaration: match[2].trim(), source: 'dependency manifest; actual call sites are separate edges' }, `integration:${match[1]}`);
  for (const file of dartFiles) {
    const text = sourceTexts.get(file) || '';
    const packageMatch = new RegExp(`from ['"]package:${match[1]}(?:/|['"])`).exec(text);
    if (packageMatch) addEdge(modules.get(file).id, node.id, 'imports-integration', evidence(file, lineAt(text, packageMatch.index), 'direct'));
  }
}

const npmManifestText = sourceTexts.get('package.json') || '';
if (npmManifestText) {
  try {
    const npmManifest = JSON.parse(npmManifestText);
    for (const section of ['dependencies', 'devDependencies']) {
      for (const [packageName, version] of Object.entries(npmManifest[section] || {})) {
        const offset = npmManifestText.indexOf(`"${packageName}"`);
        const node = addNode('integration', packageName, 'package.json', lineAt(npmManifestText, Math.max(0, offset)), {
          declaration: version,
          manifestSection: section,
          source: 'Node package manifest; actual call sites are separate edges',
        }, `integration:npm:${packageName}`);
        for (const file of [...rootScripts, ...toolFiles, ...functionFiles, ...rulesTestFiles]) {
          const text = sourceTexts.get(file) || '';
          const importStrings = [`require('${packageName}')`, `require("${packageName}")`, `from '${packageName}'`, `from "${packageName}"`];
          const importIndex = importStrings.map((value) => text.indexOf(value)).filter((value) => value >= 0).sort((left, right) => left - right)[0];
          if (importIndex != null && modules.has(file)) addEdge(modules.get(file).id, node.id, 'imports-integration', evidence(file, lineAt(text, importIndex), 'direct'));
        }
      }
    }
  } catch (error) {
    unresolved.push({ type: 'npm-manifest', file: 'package.json', line: 1, note: error.message });
  }
}

const integrationMarkers = [
  ['Firebase Hosting', 'firebase.json', /"hosting"\s*:/],
  ['Firestore Rules and Indexes', 'firebase.json', /"firestore"\s*:/],
  ['Android release pipeline', '.github/workflows/build-apk.yml', /./],
  ['Firebase deployment workflows', '.github/workflows/deploy-web.yml', /./],
];
for (const [name, file, pattern] of integrationMarkers) {
  const text = sourceTexts.get(file) || read(file) || '';
  const match = pattern.exec(text);
  if (match) addNode('integration', name, file, lineAt(text, match.index), { declaration: 'configuration/workflow' }, `integration:${name}`);
}

const workflowNodes = [];
for (const file of workflowFiles) {
  const text = sourceTexts.get(file) || '';
  const line = lineAt(text, Math.max(0, text.indexOf('name:')));
  const workflowName = text.match(/^name:\s*(.+)$/m)?.[1]?.trim() || path.basename(file);
  const node = addNode('workflow', workflowName, file, line, { trigger: text.match(/^on:\s*(.+)$/m)?.[1]?.trim() || 'see workflow source' }, `workflow:${file}`);
  workflowNodes.push(node);
  for (const step of text.matchAll(/^\s*-\s*name:\s*(.+)$/gm)) {
    const stepNode = addNode('pipeline-step', step[1].trim(), file, lineAt(text, step.index), { workflow: workflowName }, `step:${file}:${lineAt(text, step.index)}`);
    addEdge(node.id, stepNode.id, 'contains-step', evidence(file, lineAt(text, step.index)));
  }
}

const ruleFile = 'firestore.rules';
const ruleText = sourceTexts.get(ruleFile) || read(ruleFile) || '';
function matchingBrace(text, openIndex) {
  let depth = 0;
  for (let i = openIndex; i < text.length; i++) {
    if (text[i] === '{') depth++;
    if (text[i] === '}') {
      depth--;
      if (depth === 0) return i;
    }
  }
  return text.length - 1;
}
const ruleBlocks = [];
for (const match of ruleText.matchAll(/\bmatch\s+(\S+)\s+\{/g)) {
  const openIndex = match.index + match[0].lastIndexOf('{');
  ruleBlocks.push({ path: match[1], start: match.index, open: openIndex, end: matchingBrace(ruleText, openIndex), line: lineAt(ruleText, match.index) });
}
const ruleNodesByPath = new Map();
for (const block of ruleBlocks) {
  const node = addNode('rule-match', block.path, ruleFile, block.line, { default: 'deny unless allow clause matches' }, `rule-match:${block.path}:${block.line}`);
  ruleNodesByPath.set(`${block.path}:${block.line}`, node);
  for (const segment of block.path.split('/').filter(Boolean)) {
    if (segment.includes('{')) continue;
    const collection = [...collectionNodesByConstant.values()].find((candidate) => candidate.name === segment);
    if (collection) addEdge(node.id, collection.id, 'secures-collection', evidence(ruleFile, block.line));
  }
}
for (const match of ruleText.matchAll(/\ballow\s+([^:;]+):\s*if\s*([\s\S]*?);/g)) {
  const block = [...ruleBlocks].reverse().find((item) => item.start < match.index && item.end > match.index);
  const line = lineAt(ruleText, match.index);
  const operation = match[1].replace(/\s+/g, ' ').trim();
  const node = addNode('security-rule', `${operation} ${block?.path || 'unscoped'}`, ruleFile, line, {
    match: block?.path || null,
    condition: match[2].replace(/\s+/g, ' ').trim().slice(0, 260),
  }, `security-rule:${block?.path || 'unscoped'}:${operation}:${line}`);
  if (block) {
    const parent = ruleNodesByPath.get(`${block.path}:${block.line}`);
    if (parent) addEdge(parent.id, node.id, 'contains-allow-clause', evidence(ruleFile, line));
  }
}

const indexes = [];
try {
  const indexPath = 'firestore.indexes.json';
  const indexText = sourceTexts.get(indexPath) || read(indexPath) || '';
  const parsed = JSON.parse(indexText);
  const occurrences = new Map();
  for (const item of parsed.indexes || []) {
    const group = item.collectionGroup;
    const ordinal = occurrences.get(group) || 0;
    occurrences.set(group, ordinal + 1);
    let cursor = 0;
    for (let count = 0; count <= ordinal; count++) cursor = indexText.indexOf(`"collectionGroup": "${group}"`, cursor) + 1;
    const fields = (item.fields || []).map((field) => ({ path: field.fieldPath, order: field.order || field.arrayConfig }));
    const line = lineAt(indexText, Math.max(0, cursor - 1));
    const node = addNode('index', `${group}: ${fields.map((field) => `${field.path} ${field.order}`).join(', ')}`, indexPath, line, { collectionGroup: group, queryScope: item.queryScope, fields }, `index:${group}:${fields.map((field) => field.path + ':' + field.order).join('|')}`);
    indexes.push({ node, group, fields, queryScope: item.queryScope });
  }
  for (const override of parsed.fieldOverrides || []) {
    for (const field of override.indexes || []) {
      const fieldOffset = indexText.indexOf(`"fieldPath": "${override.fieldPath}"`);
      const node = addNode('index-override', `${override.collectionGroup}.${override.fieldPath} ${field.order} ${field.queryScope}`, indexPath, lineAt(indexText, Math.max(0, fieldOffset)), { ...override, configuration: field }, `index-override:${override.collectionGroup}:${override.fieldPath}:${field.order}:${field.queryScope}`);
      indexes.push({ node, group: override.collectionGroup, fields: [{ path: override.fieldPath, order: field.order }], queryScope: field.queryScope });
    }
  }
} catch (error) {
  unresolved.push({ type: 'index-parse', file: 'firestore.indexes.json', line: 1, note: error.message });
}

const queryNodes = [];
for (const file of dartFiles.filter((file) => file.startsWith('app/lib/providers/'))) {
  const text = sourceTexts.get(file) || '';
  const collectionMatches = [...text.matchAll(/\.collection(?:Group)?\(\s*Collections\.(\w+)\s*\)/g)];
  const whereMatches = [...text.matchAll(/\.where\(\s*['"]([^'"]+)['"]/g)];
  const orderMatches = [...text.matchAll(/\.orderBy\(\s*['"]([^'"]+)['"]/g)];
  const emitted = new Set();
  const nearestCollection = (offset) => {
    const prior = collectionMatches.filter((candidate) => candidate.index < offset).at(-1) || collectionMatches[0];
    if (!prior) return null;
    const name = collectionNodesByConstant.get(prior[1])?.name;
    return name ? { source: prior, name } : null;
  };
  const emitQuery = (anchor, kind) => {
    const collection = nearestCollection(anchor.index);
    if (!collection) return;
    const priorOrder = orderMatches.filter((item) => item.index < anchor.index).at(-1);
    const start = Math.max(collection.source.index, priorOrder?.index || collection.source.index, anchor.index - 900);
    const snippetEnd = kind === 'order' ? anchor.index + anchor[0].length : Math.min(text.length, anchor.index + 900);
    const snippet = text.slice(start, snippetEnd);
    const whereFields = [...new Set([...snippet.matchAll(/\.where\(\s*['"]([^'"]+)['"]/g)].map((item) => item[1]))];
    const orderFields = kind === 'order'
      ? [anchor[1]]
      : [...new Set([...snippet.matchAll(/\.orderBy\(\s*['"]([^'"]+)['"]/g)].map((item) => item[1]))];
    const line = lineAt(text, anchor.index);
    const id = `query:${file}:${line}:${kind}`;
    if (emitted.has(id)) return;
    emitted.add(id);
    const required = [...new Set([...whereFields, ...orderFields])];
    const matching = indexes.filter((index) => index.group === collection.name && required.every((field) => index.fields.some((value) => value.path === field)));
    const pairs = whereFields.flatMap((whereField) => orderFields.filter((orderField) => orderField !== whereField).map((orderField) => [whereField, orderField]));
    const missingPairs = pairs.filter(([whereField, orderField]) => !matching.some((index) => index.fields.some((field) => field.path === whereField) && index.fields.some((field) => field.path === orderField)));
    const node = addNode('query', `${collection.name} where ${whereFields.join(',')} order ${orderFields.join(',')}`, file, line, {
      collection: collection.name,
      whereFields,
      orderFields,
      limit: snippet.match(/\.limit\(\s*(\d+)\s*\)/)?.[1] || null,
      candidateIndexCount: matching.length,
      missingPairs,
      heuristic: 'Nearest prior collection reference plus nearby clauses; inspect for query variables, multiple queries per provider, and dynamic fields.',
    }, id);
    queryNodes.push(node);
    addEdge(modules.get(file).id, node.id, 'declares-query-candidate', evidence(file, line, 'inferred', 'Query-to-provider association is static and may over-connect within a file.'));
    const collectionNode = [...collectionNodesByConstant.values()].find((entry) => entry.name === collection.name);
    if (collectionNode) addEdge(node.id, collectionNode.id, 'queries-collection', evidence(file, line, 'inferred', 'Collection inferred from nearest prior constant reference.'));
    for (const index of matching) addEdge(node.id, index.node.id, 'candidate-covered-by-index', evidence('firestore.indexes.json', index.node.source.line, 'inferred', 'Field-set heuristic; confirm the Firestore query planner result.'));
    if (missingPairs.length) node.risk.push('possible composite index gap; static heuristic only');
  };
  for (const match of orderMatches) emitQuery(match, 'order');
  for (const match of whereMatches) {
    if (!orderMatches.some((order) => order.index > match.index && order.index - match.index < 900)) emitQuery(match, 'where');
  }
}

const providerQueryClauseScan = {
  providerFiles: dartFiles.filter((file) => file.startsWith('app/lib/providers/')).length,
  whereClauses: dartFiles.filter((file) => file.startsWith('app/lib/providers/')).reduce((sum, file) => sum + [...(sourceTexts.get(file) || '').matchAll(/\.where\(/g)].length, 0),
  orderByClauses: dartFiles.filter((file) => file.startsWith('app/lib/providers/')).reduce((sum, file) => sum + [...(sourceTexts.get(file) || '').matchAll(/\.orderBy\(/g)].length, 0),
  collectionCalls: dartFiles.filter((file) => file.startsWith('app/lib/providers/')).reduce((sum, file) => sum + [...(sourceTexts.get(file) || '').matchAll(/\.collection(?:Group)?\(/g)].length, 0),
};

const testNodes = [];
const testPattern = /\b(testWidgets|test|it|describe|group)\s*\(\s*(['"])([^'"\n]+)\2/g;
for (const file of [...appTestFiles, ...rulesTestFiles]) {
  const text = sourceTexts.get(file) || '';
  let matches = 0;
  for (const match of text.matchAll(testPattern)) {
    matches++;
    const line = lineAt(text, match.index);
    const category = ['group', 'describe'].includes(match[1]) ? 'test-suite' : 'test';
    const node = addNode(category, match[3], file, line, {
      framework: file.endsWith('.dart') ? 'Flutter/Dart test declaration' : 'Mocha/Rules Emulator declaration',
      declarationKind: match[1],
      status: 'not executed by discovery generator',
    }, `test:${file}:${line}:${match[1]}:${match[3]}`);
    testNodes.push(node);
    const module = modules.get(file);
    if (module) addEdge(node.id, module.id, 'declared-in', evidence(file, line));
  }
  if (matches === 0) {
    const node = addNode('test-file', file, file, 1, { status: 'test file scanned; no declaration pattern found' }, `test-file:${file}`);
    testNodes.push(node);
  }
}

for (const node of [...screenNodesByName.values(), ...widgetNodesByName.values(), ...providerNodesByName.values(), ...modelNodesByName.values()]) {
  const sourceText = sourceTexts.get(node.source.path) || '';
  const symbolName = node.name;
  let occurrences = 0;
  for (const file of dartFiles) {
    const text = sourceTexts.get(file) || '';
    const regex = new RegExp(`\\b${symbolName}\\b`, 'g');
    for (const match of text.matchAll(regex)) {
      if (file === node.source.path && lineAt(text, match.index) === node.source.line) continue;
      occurrences++;
      break;
    }
    if (occurrences) break;
  }
  if (!occurrences) node.risk.push('possible orphan: no other Dart source reference detected');
}

const directDocVersions = [];
for (const file of ['README.md', 'app/README.md', 'MASTER_BLUEPRINT.md', 'AGENTS.md', 'CLAUDE.md', 'CHANGELOG.md']) {
  const text = read(file);
  if (!text) continue;
  const version = text.slice(0, 1600).match(/v?(\d+\.\d+\.\d+\+\d+)/)?.[1] || text.slice(0, 1600).match(/(\d+\.\d+\.\d+\+\d+)/)?.[1] || null;
  directDocVersions.push({ file, version, current: version ? version === currentVersion : null });
}

const reviewedNotes = JSON.parse(read('audits/application-map/reviewed-notes.json') || '{"documentEvidence":[],"verification":[]}');

const docs = [];
for (const file of documentationFiles) {
  const text = read(file);
  if (text === null) continue;
  const title = text.match(/^#\s+(.+)$/m)?.[1] || path.basename(file);
  const date = text.match(/(?:Last updated|Date|Plan date|Audit date):\s*([^\n]+)/i)?.[1]?.trim() || null;
  const line = lineAt(text, Math.max(0, text.indexOf(title)));
  docs.push(addNode('documentation', title, file, line, {
    date,
    mentionsProposals: /proposed|not started|future enhancement|deferred|pending/i.test(text),
  }, `doc:${file}`));
}

const git = (args) => {
  try { return execFileSync('git', args, { cwd: root, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim(); }
  catch { return null; }
};
const head = git(['rev-parse', 'HEAD']);
const branch = git(['branch', '--show-current']);
const rawStatus = execFileSync('git', ['status', '--short'], { cwd: root, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).replaceAll('\r', '');
const statusLines = rawStatus.split('\n').filter(Boolean)
  .filter((line) => !line.includes('audits/application-map/'));
const dirtyFiles = statusLines.map((line) => line.slice(3).trim()).filter((file) => !file.startsWith('audits/'));
const coverage = {
  sourceFiles: allScanned.length,
  firestoreCollectionConstants: collectionConstants.size,
  uniqueFirestoreCollections: new Set(collectionNodesByConstant.values()).size,
  dartLibraryFiles: dartFiles.length,
  dartTestFiles: appTestFiles.length,
  rulesTestFiles: rulesTestFiles.length,
  functionFiles: functionFiles.length,
  functionManifests: functionManifests.length,
  workflowFiles: workflowFiles.length,
  androidBuildFiles: androidBuildFiles.length,
  webShellFiles: webShellFiles.length,
  rootScripts: rootScripts.length,
  fastlaneFiles: fastlaneFiles.length,
  documentationFiles: documentationFiles.length,
  providerQueryClauseScan,
  excluded,
  inaccessible: [],
  dirtyFiles,
  sourceCommit: head,
  branch,
  remoteMainVerifiedDuringDiscovery: '79c107838fea38132d40ce2d3276b03ac59c9080',
  remoteVerification: 'git ls-remote refs/heads/main matched local HEAD during discovery; generator does not contact upstream on later runs.',
};

const categories = [...new Set(nodes.map((node) => node.category))].sort();
const counts = Object.fromEntries(categories.map((category) => [category, nodes.filter((node) => node.category === category).length]));
const orphanCandidates = nodes.filter((node) => node.risk.some((risk) => risk.startsWith('possible orphan')));
const riskNodes = nodes.filter((node) => node.risk.length || (node.details?.missingPairs?.length));
const citationIssues = [];
const citationLineCounts = new Map();
function validateCitation(item, owner) {
  if (!item?.path || !Number.isInteger(item.line) || item.line < 1) {
    citationIssues.push({ owner, path: item?.path || null, line: item?.line || null, problem: 'missing path or invalid line number' });
    return;
  }
  let lineCount = citationLineCounts.get(item.path);
  if (lineCount == null) {
    const source = read(item.path);
    if (source == null) {
      citationIssues.push({ owner, path: item.path, line: item.line, problem: 'source file not readable' });
      return;
    }
    lineCount = source.split('\n').length;
    citationLineCounts.set(item.path, lineCount);
  }
  if (item.line > lineCount) citationIssues.push({ owner, path: item.path, line: item.line, problem: `line exceeds source length ${lineCount}` });
}
for (const node of nodes) if (node.source) validateCitation(node.source, node.id);
const nodeIds = new Set(nodes.map((node) => node.id));
for (const edge of edges) {
  if (!nodeIds.has(edge.from) || !nodeIds.has(edge.to)) citationIssues.push({ owner: edge.id, problem: 'edge endpoint missing from inventory' });
  if (!edge.evidence.length) citationIssues.push({ owner: edge.id, problem: 'edge has no source evidence' });
  for (const item of edge.evidence) validateCitation(item, edge.id);
}
const citationValidation = {
  nodeCitationsChecked: nodes.filter((node) => node.source).length,
  edgeCitationsChecked: edges.reduce((sum, edge) => sum + edge.evidence.length, 0),
  edgeEndpointsChecked: edges.length,
  issues: citationIssues,
  passed: citationIssues.length === 0,
};
const verification = {
  discoveryRun: 'static scan only; tests/analyzers/builds not invoked by generator',
  currentTreeTestStatus: 'full suite not run; see reviewedEvidence for focused results and prior-release caveat',
  lastKnownRelease: { version: '3.9.79+705', commit: '79c1078', status: 'previous release evidence; not a validation of the current dirty tree' },
  currentWip: dirtyFiles,
  providerCycleCandidateCount: providerCycles.length,
  reviewedEvidence: reviewedNotes.verification || [],
};

const inventory = {
  schemaVersion: 1,
  generatedAt,
  application: 'Footwear ERP',
  source: { repository: 'engremran07/footwear', head, branch, workingTreeDirty: dirtyFiles.length > 0 },
  version: currentVersion,
  discoveryCoverage: coverage,
  citationValidation,
  counts,
  nodes,
  edges,
  queries: queryNodes.map((node) => ({ id: node.id, source: node.source, ...node.details, risk: node.risk })),
  queryClauseScan: providerQueryClauseScan,
  providerCycles,
  recoveryPaths: recoveryNodes.map((node) => ({ id: node.id, name: node.name, source: node.source, details: node.details })),
  reviewedNotes,
  documentationVersions: directDocVersions,
  orphanCandidates: orphanCandidates.map((node) => ({ id: node.id, category: node.category, name: node.name, source: node.source, risk: node.risk })),
  riskCandidates: riskNodes.map((node) => ({ id: node.id, category: node.category, name: node.name, source: node.source, risk: node.risk, details: node.details })),
  unresolved,
  verification,
  limitations,
};

function mkdir(file) { fs.mkdirSync(path.dirname(file), { recursive: true }); }
function write(relative, content) {
  const target = path.join(outputDir, relative);
  mkdir(target);
  fs.writeFileSync(target, content, 'utf8');
}
function escapeMermaid(value) {
  return String(value).replaceAll('"', "'").replace(/[\r\n]/g, ' ').replace(/[<>]/g, '');
}
function mermaidNode(id, label) { return `  ${id}["${escapeMermaid(label)}"]`; }
function evidenceLabel(file, line) { return `${file}#L${line}`; }

function flowDiagram(title, lines) {
  return `---\ntitle: ${title}\n---\nflowchart LR\n${lines.join('\n')}\n`;
}

const functionLine = (file, symbol) => {
  const text = read(file) || '';
  const escaped = symbol.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const patterns = [
    new RegExp(`^\\s*(?:static\\s+)?(?:Future(?:<[^\\n]+>)?|void|bool|int|double|String|Widget|Map<[^\\n]+>|List<[^\\n]+>|[A-Z][A-Za-z0-9_<>,?. ]*)\\s+${escaped}\\s*\\(`, 'm'),
    new RegExp(`^\\s*(?:final|late\\s+final|const|var)\\s+${escaped}\\b`, 'm'),
    new RegExp(`^\\s*[A-Za-z0-9_<>,? ]+\\s+get\\s+${escaped}\\b`, 'm'),
    new RegExp(`\\b${escaped}\\s*\\(`),
    new RegExp(`\\b${escaped}\\b`),
  ];
  for (const pattern of patterns) {
    const match = pattern.exec(text);
    if (match) return lineAt(text, match.index);
  }
  return 1;
};
const diagrams = {
  'architecture.mmd': flowDiagram('Source architecture (static map)', [
    `  UI["Flutter screens/widgets · ${evidenceLabel('app/lib/screens/dashboard_screen.dart', functionLine('app/lib/screens/dashboard_screen.dart', 'dashboardStatsProvider'))}"]`,
    `  Router["GoRouter and role redirects · ${evidenceLabel(routeFile, Math.max(1, lineAt(routerText, routerText.indexOf('final appRouterProvider'))))}"]`,
    `  Auth["Firebase Auth and SessionGuard · ${evidenceLabel('app/lib/providers/auth_provider.dart', functionLine('app/lib/providers/auth_provider.dart', 'signIn'))}"]`,
    `  State["Riverpod providers/notifiers · ${evidenceLabel('app/lib/providers/tenant_provider.dart', functionLine('app/lib/providers/tenant_provider.dart', 'registerCurrentAccess'))}"]`,
    `  Rules["Firestore Rules · ${evidenceLabel('firestore.rules', Math.max(1, lineAt(ruleText, ruleText.indexOf('match /users/'))))}"]`,
    `  Data["Firestore collections/indexes · ${evidenceLabel('app/lib/core/constants/collections.dart', collectionNodesByConstant.get('users')?.source.line || 1)}"]`,
    `  Export["PDF/XLSX/print/share · ${evidenceLabel('app/lib/widgets/export_sheet.dart', functionLine('app/lib/widgets/export_sheet.dart', 'show'))}"]`,
    `  Router -->|${evidenceLabel(routeFile, Math.max(1, lineAt(routerText, routerText.indexOf('final appRouterProvider'))))}| UI`,
    `  UI -->|${evidenceLabel('app/lib/screens/dashboard_screen.dart', functionLine('app/lib/screens/dashboard_screen.dart', 'dashboardStatsProvider'))}| State`,
    `  Auth -->|${evidenceLabel('app/lib/providers/auth_provider.dart', functionLine('app/lib/providers/auth_provider.dart', 'signIn'))}| State`,
    `  State -->|${evidenceLabel('app/lib/providers/tenant_provider.dart', functionLine('app/lib/providers/tenant_provider.dart', 'registerCurrentAccess'))}| Data`,
    `  Rules -->|${evidenceLabel('firestore.rules', Math.max(1, lineAt(ruleText, ruleText.indexOf('match /users/'))))}| Data`,
    `  State -->|${evidenceLabel('app/lib/screens/reports_screen.dart', functionLine('app/lib/screens/reports_screen.dart', 'ExportSheet.show'))}| Export`,
  ]),
  'feature-dependencies.mmd': flowDiagram('Feature dependencies (representative source paths)', [
    `  Auth["Authentication/access · ${evidenceLabel('app/lib/providers/auth_provider.dart', functionLine('app/lib/providers/auth_provider.dart', 'signIn'))}"]`,
    `  Workspace["Workspace/user admin · ${evidenceLabel('app/lib/screens/tenant_management_screen.dart', functionLine('app/lib/screens/tenant_management_screen.dart', 'build'))}"]`,
    `  Routes["Routes/assignments · ${evidenceLabel('app/lib/providers/route_provider.dart', functionLine('app/lib/providers/route_provider.dart', 'routesProvider'))}"]`,
    `  Inventory["Warehouse/seller stock · ${evidenceLabel('app/lib/providers/product_provider.dart', functionLine('app/lib/providers/product_provider.dart', 'transferToSeller'))}"]`,
    `  Shops["Shops/ledger · ${evidenceLabel('app/lib/providers/shop_provider.dart', functionLine('app/lib/providers/shop_provider.dart', 'sellerAllShopsProvider'))}"]`,
    `  Invoices["Stock/non-stock/receipt invoices · ${evidenceLabel('app/lib/providers/invoice_provider.dart', functionLine('app/lib/providers/invoice_provider.dart', 'createSaleInvoice'))}"]`,
    `  Finance["Balances/transaction ledger · ${evidenceLabel('app/lib/providers/transaction_provider.dart', functionLine('app/lib/providers/transaction_provider.dart', 'create'))}"]`,
    `  Reports["Reports/exports · ${evidenceLabel('app/lib/screens/reports_screen.dart', functionLine('app/lib/screens/reports_screen.dart', 'ExportSheet.show'))}"]`,
    `  Auth -->|${evidenceLabel('app/lib/providers/auth_provider.dart', functionLine('app/lib/providers/auth_provider.dart', 'signIn'))}| Workspace`,
    `  Workspace -->|${evidenceLabel('app/lib/providers/user_provider.dart', functionLine('app/lib/providers/user_provider.dart', 'createUser'))}| Routes`,
    `  Routes -->|${evidenceLabel('app/lib/providers/shop_provider.dart', functionLine('app/lib/providers/shop_provider.dart', 'sellerAllShopsProvider'))}| Shops`,
    `  Inventory -->|${evidenceLabel('app/lib/providers/invoice_provider.dart', functionLine('app/lib/providers/invoice_provider.dart', 'createSaleInvoice'))}| Invoices`,
    `  Invoices -->|${evidenceLabel('app/lib/providers/invoice_provider.dart', functionLine('app/lib/providers/invoice_provider.dart', 'createSaleInvoice'))}| Finance`,
    `  Shops -->|${evidenceLabel('app/lib/providers/transaction_provider.dart', functionLine('app/lib/providers/transaction_provider.dart', 'shopTransactionsProvider'))}| Reports`,
    `  Invoices -->|${evidenceLabel('app/lib/core/utils/pdf_export.dart', functionLine('app/lib/core/utils/pdf_export.dart', 'generateInvoicePdf'))}| Reports`,
    `  Auth -->|${evidenceLabel('app/lib/providers/tenant_provider.dart', functionLine('app/lib/providers/tenant_provider.dart', 'registerCurrentAccess'))}| Inventory`,
  ]),
  'role-journeys.mmd': flowDiagram('Role journeys (source-derived; runtime auth unverified)', [
    `  Start([Login · ${evidenceLabel('app/lib/screens/login_screen.dart', functionLine('app/lib/screens/login_screen.dart', '_submit'))}]) -->|${evidenceLabel('app/lib/providers/auth_provider.dart', functionLine('app/lib/providers/auth_provider.dart', 'signIn'))}| Profile[users/{uid} profile]`,
    `  Profile -->|${evidenceLabel('app/lib/providers/auth_provider.dart', functionLine('app/lib/providers/auth_provider.dart', 'signIn'))}| Role{Normalized role}`, 
    `  Role -->|${evidenceLabel('app/lib/models/user_model.dart', functionLine('app/lib/models/user_model.dart', 'isSeller'))}| Seller[Seller: tenant + route assignment]`,
    `  Role -->|${evidenceLabel('app/lib/models/user_model.dart', functionLine('app/lib/models/user_model.dart', 'isTenantAdmin'))}| TenantAdmin[Tenant admin: own workspace]`,
    `  Role -->|${evidenceLabel('app/lib/models/user_model.dart', functionLine('app/lib/models/user_model.dart', 'isAdmin'))}| LegacyAdmin[Admin / manager: tenant-scoped operations]`,
    `  Role -->|${evidenceLabel('firestore.rules', Math.max(1, lineAt(ruleText, ruleText.indexOf('function isSuperAdmin'))))}| SuperAdmin[Super-admin: platform metadata]`,
    `  Seller -->|${evidenceLabel('app/lib/providers/tenant_provider.dart', functionLine('app/lib/providers/tenant_provider.dart', 'registerCurrentAccess'))}| Access[Device/session registration]`,
    `  TenantAdmin -->|${evidenceLabel('app/lib/providers/tenant_provider.dart', functionLine('app/lib/providers/tenant_provider.dart', 'registerCurrentAccess'))}| Access`,
    `  LegacyAdmin -->|${evidenceLabel('app/lib/providers/tenant_provider.dart', functionLine('app/lib/providers/tenant_provider.dart', 'registerCurrentAccess'))}| Access`,
    `  SuperAdmin -->|${evidenceLabel('app/lib/providers/tenant_provider.dart', functionLine('app/lib/providers/tenant_provider.dart', 'registerPlatformSession'))}| PlatformSession[Separate platform session]`,
    `  Access -->|${evidenceLabel('app/lib/core/utils/session_access_policy.dart', functionLine('app/lib/core/utils/session_access_policy.dart', 'requiresDeviceApproval'))}| Pairing{Seller pairing enabled?}`, 
    `  Pairing -->|${evidenceLabel('app/lib/providers/tenant_provider.dart', functionLine('app/lib/providers/tenant_provider.dart', 'approveDevice'))}| Approval[Admin approval surface]`,
    `  Pairing -->|${evidenceLabel('app/lib/providers/tenant_provider.dart', functionLine('app/lib/providers/tenant_provider.dart', 'registerCurrentAccess'))}| Business[Tenant business UI]`,
    `  SuperAdmin -->|${evidenceLabel('app/lib/providers/auth_provider.dart', functionLine('app/lib/providers/auth_provider.dart', 'selectWorkspace'))}| Business`,
    `  Business -->|${evidenceLabel('firestore.rules', Math.max(1, lineAt(ruleText, ruleText.indexOf('function isActiveUser'))))}| Rules[Firestore Rules re-check tenant/role scope]`,
  ]),
  'critical-data-flows.mmd': flowDiagram('Critical data flows (documented and source-linked)', [
    `  SaleUI["CreateSaleInvoiceScreen · ${evidenceLabel('app/lib/screens/create_sale_invoice_screen.dart', functionLine('app/lib/screens/create_sale_invoice_screen.dart', '_submit'))}"] -->|${evidenceLabel('app/lib/screens/create_sale_invoice_screen.dart', functionLine('app/lib/screens/create_sale_invoice_screen.dart', '_submit'))}| SaleProvider[InvoiceNotifier.createSaleInvoice]`,
    `  SaleProvider["InvoiceNotifier.createSaleInvoice · ${evidenceLabel('app/lib/providers/invoice_provider.dart', functionLine('app/lib/providers/invoice_provider.dart', 'createSaleInvoice'))}"] -->|${evidenceLabel('app/lib/providers/invoice_provider.dart', functionLine('app/lib/providers/invoice_provider.dart', 'createSaleInvoice'))}| SaleInvoice[Invoice + counter]`,
    `  SaleProvider -->|${evidenceLabel('app/lib/providers/invoice_provider.dart', functionLine('app/lib/providers/invoice_provider.dart', 'createSaleInvoice'))}| Ledger[Transactions + shop.balance]`,
    `  SaleProvider -->|${evidenceLabel('app/lib/providers/invoice_provider.dart', functionLine('app/lib/providers/invoice_provider.dart', 'createSaleInvoice'))}| Stock[Seller inventory + audit row]`,
    `  ReceiptUI["Cash receipt mode · ${evidenceLabel('app/lib/providers/invoice_provider.dart', functionLine('app/lib/providers/invoice_provider.dart', 'createCashReceipt'))}"] -->|${evidenceLabel('app/lib/providers/invoice_provider.dart', functionLine('app/lib/providers/invoice_provider.dart', 'createCashReceipt'))}| ReceiptProvider[InvoiceNotifier.createCashReceipt]`,
    `  ReceiptProvider -->|${evidenceLabel('app/lib/providers/invoice_provider.dart', functionLine('app/lib/providers/invoice_provider.dart', 'createCashReceipt'))}| ReceiptInvoice[Receipt invoice + counter]`,
    `  ReceiptProvider -->|${evidenceLabel('app/lib/providers/invoice_provider.dart', functionLine('app/lib/providers/invoice_provider.dart', 'createCashReceipt'))}| Ledger`,
    `  SellerLogin["AuthNotifier.signIn · ${evidenceLabel('app/lib/providers/auth_provider.dart', functionLine('app/lib/providers/auth_provider.dart', 'signIn'))}"] -->|${evidenceLabel('app/lib/providers/tenant_provider.dart', functionLine('app/lib/providers/tenant_provider.dart', 'registerCurrentAccess'))}| AccessProvider[registerCurrentAccess]`,
    `  AccessProvider -->|${evidenceLabel('app/lib/providers/tenant_provider.dart', functionLine('app/lib/providers/tenant_provider.dart', 'registerCurrentAccess'))}| DeviceSlots[users/{uid}/device_registrations]`,
    `  AccessProvider -->|${evidenceLabel('app/lib/providers/tenant_provider.dart', functionLine('app/lib/providers/tenant_provider.dart', 'registerCurrentAccess'))}| SessionSlots[users/{uid}/sessions]`,
    `  DeviceSlots -->|${evidenceLabel('firestore.rules', functionLine('firestore.rules', 'sessionDeviceIsRegistered'))}| Rules[Firestore Rules validate owner/tenant/status/slot]`,
    `  SessionSlots -->|${evidenceLabel('firestore.rules', functionLine('firestore.rules', 'sessionRecordFieldsAreValid'))}| Rules`,
  ]),
};

for (const [name, content] of Object.entries(diagrams)) {
  const citationPattern = /([A-Za-z0-9_./-]+\.(?:dart|rules|json|ya?ml|xml|html))#L(\d+)/g;
  for (const match of content.matchAll(citationPattern)) {
    citationValidation.diagramCitationsChecked = (citationValidation.diagramCitationsChecked || 0) + 1;
    validateCitation({ path: match[1], line: Number(match[2]) }, `diagram:${name}`);
  }
  write(`diagrams/${name}`, content);
}
citationValidation.issues = citationIssues;
citationValidation.passed = citationIssues.length === 0;

function compareBaseline(current) {
  const baselinePath = path.join(outputDir, 'baseline.json');
  const resetRequested = process.argv.includes('--reset-baseline');
  if (!fs.existsSync(baselinePath) || resetRequested) {
    fs.writeFileSync(baselinePath, `${JSON.stringify(current, null, 2)}\n`, 'utf8');
    return { status: resetRequested ? 'reset' : 'initialized', baseline: 'baseline.json', message: resetRequested ? 'Baseline refreshed from the current working tree by explicit request.' : 'Initial static inventory snapshot created from the current working tree.' };
  }
  let baseline;
  try { baseline = JSON.parse(fs.readFileSync(baselinePath, 'utf8')); }
  catch (error) { return { status: 'error', message: `Could not parse baseline.json: ${error.message}` }; }
  const mapNodes = (items) => new Map((items || []).map((node) => [node.id, JSON.stringify({ category: node.category, name: node.name, source: node.source, details: node.details })]));
  const oldNodes = mapNodes(baseline.nodes);
  const newNodes = mapNodes(current.nodes);
  const added = [...newNodes.keys()].filter((id) => !oldNodes.has(id));
  const removed = [...oldNodes.keys()].filter((id) => !newNodes.has(id));
  const changed = [...newNodes.keys()].filter((id) => oldNodes.has(id) && oldNodes.get(id) !== newNodes.get(id));
  const edgeSet = (items) => new Set((items || []).map((edge) => `${edge.from}|${edge.to}|${edge.type}|${edge.confidence}`));
  const oldEdges = edgeSet(baseline.edges);
  const newEdges = edgeSet(current.edges);
  return {
    status: 'compared',
    baselineCommit: baseline.source?.head || null,
    currentCommit: current.source?.head || null,
    addedNodes: added,
    removedNodes: removed,
    changedNodes: changed,
    addedEdges: [...newEdges].filter((edge) => !oldEdges.has(edge)),
    removedEdges: [...oldEdges].filter((edge) => !newEdges.has(edge)),
    note: 'Comparison uses stable node ids and source/declaration metadata; generated timestamps and dirty audit outputs are excluded.',
  };
}

const comparison = compareBaseline(inventory);
inventory.baselineComparison = {
  status: comparison.status,
  baselineCommit: comparison.baselineCommit || head,
  addedNodeCount: comparison.addedNodes?.length || 0,
  removedNodeCount: comparison.removedNodes?.length || 0,
  changedNodeCount: comparison.changedNodes?.length || 0,
  addedEdgeCount: comparison.addedEdges?.length || 0,
  removedEdgeCount: comparison.removedEdges?.length || 0,
};

write('inventory.json', `${JSON.stringify(inventory, null, 2)}\n`);
write('comparison.json', `${JSON.stringify(comparison, null, 2)}\n`);

const summaryLines = [
  'FOOTWEAR APPLICATION DISCOVERY — STATIC SOURCE REPORT',
  `Generated: ${generatedAt}`,
  `Repository: engremran07/footwear` ,
  `Branch/commit: ${branch || 'unknown'} / ${head || 'unknown'}`,
  `Upstream main at discovery: ${coverage.remoteMainVerifiedDuringDiscovery}`,
  `App version metadata: ${currentVersion}`,
  `Dirty application files preserved: ${dirtyFiles.length ? dirtyFiles.join(', ') : 'none'}`,
  '',
  'INVENTORY COUNTS',
  `- Firestore collection constants: ${collectionConstants.size}; unique paths: ${new Set(collectionNodesByConstant.values()).size} (aliases preserved in inventory.json)`,
  ...Object.entries(counts).sort(([left], [right]) => left.localeCompare(right)).map(([name, count]) => `- ${name}: ${count}`),
  '',
  'DISCOVERY FINDINGS',
  `- Orphan candidates (heuristic only): ${orphanCandidates.length}`,
  `- Query candidates: ${queryNodes.length}; provider source scan saw ${providerQueryClauseScan.whereClauses} where clauses, ${providerQueryClauseScan.orderByClauses} orderBy clauses, and ${providerQueryClauseScan.collectionCalls} collection calls. Query-to-index mapping is heuristic, not a Firestore planner result.`,
  `- Possible index-gap candidates: ${queryNodes.filter((query) => query.risk.length).length}; provider dependency cycle candidates: ${providerCycles.length}; possible orphan declarations: ${orphanCandidates.length}. All are static heuristics.`,
  `- Unresolved route/collection/index references: ${unresolved.length}; source citation validation: ${citationValidation.passed ? 'PASS' : 'FAIL'} (${citationValidation.issues.length} issues; ${citationValidation.diagramCitationsChecked || 0} Mermaid citations).`,
  `- Current dirty paths: ${dirtyFiles.join(', ') || 'none'}. Tests are declarations unless a reviewed output below records an execution.`,
  `- Prior release evidence is for commit 79c1078 only; it does not validate the current dirty tree.`,
  '',
  'REVIEWED EXECUTION EVIDENCE',
  ...reviewedNotes.verification.map((item) => `- ${item.scope}: ${item.result} [${item.status}]`),
  '',
  'DOCUMENTATION / SOURCE DISCREPANCY CANDIDATES',
  ...reviewedNotes.documentEvidence.map((item) => `- ${item.id}: ${item.observation} Sources: ${item.sources.join(', ')}.`),
  '',
  'DOCUMENTATION VERSION SNAPSHOT',
  ...directDocVersions.map((item) => `- ${item.file}: ${item.version || 'no top-level version detected'}${item.current === true ? ' (matches app)' : item.current === false ? ' (version differs; inspect for drift)' : ' (unversioned; review content freshness)'}`),
  '',
  'LIMITATIONS',
  ...limitations.map((item) => `- ${item}`),
  '',
  'ARTIFACTS',
  '- dashboard.html: offline searchable inventory and local graph navigation',
  '- inventory.json: nodes, edges, evidence, risks, test declarations, limitations',
  '- diagrams/*.mmd: Mermaid architecture, dependencies, role journeys, and critical flows',
  '- baseline.json and comparison.json: first-run snapshot and repeatable diff',
  '- Regenerate with: node audits/application-map/generate.js',
];
write('audit-report.txt', `${summaryLines.join('\n')}\n`);

const regenerate = [
  'Footwear application map regeneration',
  '',
  'Prerequisite: Node.js 18+; no npm packages are required.',
  '',
  'From the repository root run:',
  '  node audits/application-map/generate.js',
  '',
  'The generator scans first-party Dart source/tests, Firestore Rules/indexes, Firebase configuration, workflow YAML, tool scripts, and repository documents. It skips generated build output, vendor dependencies, binary assets, and Git internals.',
  'It writes inventory.json, dashboard.html, audit-report.txt, four Mermaid files under diagrams/, and comparison.json. The first run creates baseline.json. Later runs compare against that frozen baseline without replacing it.',
  'To intentionally establish a new baseline, review the current comparison first, preserve the prior baseline separately, then run: node audits/application-map/generate.js --reset-baseline',
  '',
  'Evidence semantics:',
  '- Direct: a declaration or reference was found at the cited source line.',
  '- Inferred: a relation is suggested by identifier/import proximity or a static query heuristic; inspect its cited source before relying on it.',
  '- Risk/orphan/index flags are candidates, not confirmed defects.',
  '- The generator inventories test declarations; run tests separately and record exact outputs before claiming pass status.',
  '- Dynamic auth state, Firestore contents, app/device rendering, backend rule evaluation, and external service state remain unverified.',
].join('\n');
write('REGENERATE.txt', `${regenerate}\n`);

function htmlEscape(value) {
  return String(value ?? '').replace(/[&<>"']/g, (char) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[char]);
}
const embedded = JSON.stringify(inventory).replace(/</g, '\\u003c').replace(/\u2028/g, '\\u2028').replace(/\u2029/g, '\\u2029');
const diagramList = Object.keys(diagrams).map((name) => ({ name: name.replace('.mmd', ''), text: diagrams[name] }));
const dashboard = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Footwear ERP — Application Map</title>
<style>
:root{color-scheme:light;--ink:#18232b;--muted:#52636c;--paper:#f2f5f3;--panel:#fff;--line:#d4ddda;--teal:#006d67;--blue:#27627a;--gold:#9a6500;--red:#a43332;--green:#246b47;--shadow:0 10px 30px #18333b12}
*{box-sizing:border-box}body{margin:0;background:var(--paper);color:var(--ink);font:14px/1.45 "Segoe UI",system-ui,sans-serif}button,input,select{font:inherit;color:inherit}button{cursor:pointer}.top{background:#fff;border-bottom:1px solid var(--line);padding:18px 24px;display:flex;justify-content:space-between;align-items:center;gap:20px}.brand{display:flex;align-items:center;gap:14px}.mark{width:38px;height:38px;border-radius:8px;background:var(--teal);display:grid;place-items:center;color:#fff;font-weight:800}.top h1{font-size:18px;margin:0}.meta{color:var(--muted);font-size:12px}.status{padding:5px 9px;border-radius:99px;background:#fff2d9;color:#725000;border:1px solid #e3c982;font-size:12px;white-space:nowrap}.layout{display:grid;grid-template-columns:270px minmax(0,1fr);min-height:calc(100vh - 76px)}aside{background:#e8eeeb;border-right:1px solid var(--line);padding:16px;display:flex;flex-direction:column;gap:12px}.controls{display:grid;gap:8px}input,select{width:100%;border:1px solid #bbc9c4;border-radius:6px;background:#fff;padding:9px 10px}button.tab{border:0;text-align:left;padding:8px 10px;border-radius:5px;background:transparent}button.tab.active,button.tab:hover{background:#d1e3de;color:#004f4b}.counts{display:grid;grid-template-columns:1fr 1fr;gap:6px}.count{padding:8px;background:#fff;border:1px solid var(--line);border-radius:6px}.count strong{display:block;font-size:17px}.count span{font-size:11px;color:var(--muted)}main{padding:18px;min-width:0}.panel{background:var(--panel);border:1px solid var(--line);border-radius:7px;box-shadow:var(--shadow);padding:16px;margin-bottom:14px}.panel h2{margin:0 0 10px;font-size:16px}.sub{font-size:12px;color:var(--muted)}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(138px,1fr));gap:8px}.stat{background:#f7faf8;border:1px solid var(--line);padding:10px;border-radius:6px}.stat b{display:block;font-size:18px}.stat small{color:var(--muted)}.toolbar{display:flex;gap:8px;margin-bottom:12px;align-items:center}.toolbar input{max-width:480px}.tablewrap{overflow:auto;max-height:58vh;border:1px solid var(--line);border-radius:6px}table{border-collapse:collapse;width:100%;background:#fff}th,td{text-align:left;padding:8px 9px;border-bottom:1px solid #e4eae7;vertical-align:top}th{position:sticky;top:0;background:#edf3f0;font-size:12px;z-index:1}td{font-size:12px}a{color:#075f75;text-decoration:underline;text-underline-offset:2px}a:hover{color:#003e4e}.chip{display:inline-block;padding:2px 6px;margin:1px 3px 1px 0;border-radius:99px;background:#e5efec;color:#24554c;font-size:10px}.chip.risk{background:#fae4e1;color:#8b2d2c}.chip.inferred{background:#fff0cf;color:#745400}.detail{display:grid;grid-template-columns:minmax(0,1fr) minmax(230px,.65fr);gap:14px}.evidence{font-family:Consolas,monospace;font-size:12px}.edges{display:grid;gap:5px}.edge{padding:7px;border-left:3px solid var(--teal);background:#f4f8f6}.edge.inferred{border-color:var(--gold)}.graph{width:100%;height:460px;border:1px solid var(--line);border-radius:6px;background:radial-gradient(#cfdbd6 0.6px,transparent .6px);background-size:18px 18px}.graph text{font-size:11px;fill:var(--ink)}.graph .node{cursor:pointer}.graph .node rect{fill:#fff;stroke:#6a8981;stroke-width:1.5;rx:6}.graph .node.selected rect{fill:#d1e7e1;stroke:#006d67;stroke-width:2.5}.graph .node.risk rect{stroke:#a43332}.graph .edge{stroke:#8a9e97;stroke-width:1.2}.graph .edge.inferred{stroke:#b68422;stroke-dasharray:4 3}.diagram{white-space:pre;overflow:auto;max-height:60vh;background:#142328;color:#e7f0ed;padding:14px;border-radius:6px;font:12px/1.5 Consolas,monospace}.note{border-left:4px solid var(--gold);padding:9px 12px;background:#fff8e8;margin:8px 0}.empty{padding:30px;text-align:center;color:var(--muted)}.hidden{display:none!important}.foot{color:var(--muted);font-size:11px;margin-top:12px}@media(max-width:800px){.layout{grid-template-columns:1fr}aside{border-right:0;border-bottom:1px solid var(--line)}.detail{grid-template-columns:1fr}.top{align-items:flex-start;flex-direction:column}}
</style></head><body>
<header class="top"><div class="brand"><div class="mark">F</div><div><h1>Footwear ERP · Application Map</h1><div class="meta">Source-derived discovery · ${htmlEscape(head || 'unknown')} · ${htmlEscape(generatedAt)}</div></div></div><div class="status">Static map · runtime coverage not claimed</div></header>
<div class="layout"><aside><div class="controls"><input id="search" type="search" placeholder="Search symbols, files, features"><select id="category"><option value="">All categories</option></select><select id="feature"><option value="">All feature areas</option></select></div><button class="tab active" data-view="overview">Overview</button><button class="tab" data-view="inventory">Inventory</button><button class="tab" data-view="graph">Graph explorer</button><button class="tab" data-view="diagrams">Mermaid diagrams</button><button class="tab" data-view="limitations">Evidence & limits</button><div id="sideCounts" class="counts"></div><div class="foot">Evidence links point to repository source lines. “Inferred” relations are candidates, not proof.</div></aside>
<main><section id="overview" class="view"><div class="panel"><h2>Discovery snapshot</h2><div id="snapshot" class="grid"></div><div id="dirty" class="note"></div></div><div class="panel"><h2>Coverage signals</h2><div id="signals"></div></div><div class="panel"><h2>Highest-risk candidates</h2><div id="risks"></div></div><div class="panel"><h2>Reviewed evidence and documentation claims</h2><div id="reviewNotes"></div></div></section>
<section id="inventory" class="view hidden"><div class="panel"><h2>Repository inventory</h2><div class="toolbar"><input id="tableSearch" type="search" placeholder="Filter inventory"><span id="tableCount" class="sub"></span></div><div class="tablewrap"><table><thead><tr><th>Kind</th><th>Name</th><th>Feature</th><th>Evidence</th><th>Risk / status</th></tr></thead><tbody id="rows"></tbody></table></div></div></section>
<section id="graph" class="view hidden"><div class="panel"><h2>Local graph navigation</h2><div class="sub">Choose an inventory item to inspect direct and inferred neighbours. The complete machine-readable edge list is in inventory.json.</div><div class="toolbar"><input id="graphSearch" type="search" placeholder="Find graph node"><span id="selectedNode" class="sub">No node selected</span></div><svg id="svg" class="graph" viewBox="0 0 1000 460" role="img" aria-label="Application dependency graph"></svg><div id="nodeDetail" class="detail"></div></div></section>
<section id="diagrams" class="view hidden"><div class="panel"><h2>Mermaid diagrams</h2><div class="sub">Editable diagram sources are also saved as .mmd files in diagrams/.</div><div id="diagramList"></div></div></section>
<section id="limitations" class="view hidden"><div class="panel"><h2>Evidence boundaries</h2><ul id="limits"></ul></div><div class="panel"><h2>Unresolved static references</h2><div id="unresolved"></div></div><div class="panel"><h2>Documentation version snapshot</h2><div id="docVersions"></div></div><div class="panel"><h2>Repeatable baseline</h2><div id="baselineStatus"></div><p class="sub">See <a href="REGENERATE.txt">REGENERATE.txt</a>. The generator never replaces an existing baseline automatically.</p></div></section></main></div>
<script id="data" type="application/json">${embedded}</script>
<script>
const data=JSON.parse(document.getElementById('data').textContent);const diagrams=${JSON.stringify(diagramList)};const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));const byId=new Map(data.nodes.map(n=>[n.id,n]));let selected=null;let view='overview';const sourceHref=e=>e&&e.path?'../../'+e.path+(e.line?'#L'+e.line:''):'#';
for(const c of [...new Set(data.nodes.map(n=>n.category))].sort()){const o=document.createElement('option');o.value=c;o.textContent=c;document.getElementById('category').append(o)}for(const f of [...new Set(data.nodes.map(n=>n.feature))].sort()){const o=document.createElement('option');o.value=f;o.textContent=f;document.getElementById('feature').append(o)}
document.getElementById('sideCounts').innerHTML=Object.entries(data.counts).sort((a,b)=>b[1]-a[1]).slice(0,8).map(([n,c])=>'<div class="count"><strong>'+c+'</strong><span>'+esc(n)+'</span></div>').join('');
document.getElementById('snapshot').innerHTML=[['Dart library files',data.discoveryCoverage.dartLibraryFiles],['Routes',data.counts.route||0],['Screens',data.counts.screen||0],['Provider symbols',data.counts.provider||0],['Models',data.counts.model||0],['Firestore rule clauses',data.counts['security-rule']||0],['Composite indexes',data.counts.index||0],['Test cases',data.counts.test||0],['Test suites/groups',data.counts['test-suite']||0],['Recovery markers',data.counts['recovery-path']||0],['Query candidates',data.counts.query||0],['Provider cycle candidates',data.providerCycles.length]].map(([n,c])=>'<div class="stat"><b>'+c+'</b><small>'+esc(n)+'</small></div>').join('');
document.getElementById('dirty').innerHTML=data.source.workingTreeDirty?'<b>Dirty worktree:</b> '+data.discoveryCoverage.dirtyFiles.map(esc).join(', ')+'<br>These are included in this snapshot but are not part of commit '+esc(data.source.head)+'.':'<b>Clean worktree at snapshot.</b>';
document.getElementById('signals').innerHTML='<p>'+data.nodes.length+' nodes · '+data.edges.length+' evidence edges · '+data.discoveryCoverage.sourceFiles+' scanned first-party files.</p><p>Provider query scan: '+data.queryClauseScan.whereClauses+' where / '+data.queryClauseScan.orderByClauses+' orderBy clauses yielded '+data.queries.length+' candidates; the relationship is heuristic and not a query-planner proof.</p><p>'+data.orphanCandidates.length+' possible orphan references and '+data.queries.filter(q=>q.risk.length).length+' possible query/index gaps are review candidates. Provider cycles: '+data.providerCycles.length+' detected statically.</p><p>Current execution status: <b>'+esc(data.verification.currentTreeTestStatus)+'</b>.</p>';
document.getElementById('risks').innerHTML=data.riskCandidates.slice(0,80).map(r=>'<div class="edge inferred"><b>'+esc(r.category)+': '+esc(r.name)+'</b> '+(r.source?'<a href="'+sourceHref(r.source)+'">'+esc(r.source.path)+'#L'+r.source.line+'</a>':'')+'<br>'+r.risk.map(esc).join('; ')+'</div>').join('')||'<div class="empty">No static risk candidates generated.</div>';
const makeRow=n=>'<tr><td>'+esc(n.category)+'</td><td><button class="tab" data-node="'+esc(n.id)+'">'+esc(n.name)+'</button></td><td>'+esc(n.feature)+'</td><td>'+(n.source?'<a href="'+sourceHref(n.source)+'">'+esc(n.source.path)+'#L'+n.source.line+'</a>':'—')+'</td><td>'+n.risk.map(r=>'<span class="chip risk">'+esc(r)+'</span>').join('')+(n.category==='test'?'<span class="chip inferred">not run here</span>':'')+'</td></tr>';
function renderRows(){const q=(document.getElementById('tableSearch').value||document.getElementById('search').value).toLowerCase();const cat=document.getElementById('category').value;const feat=document.getElementById('feature').value;const list=data.nodes.filter(n=>(!cat||n.category===cat)&&(!feat||n.feature===feat)&&(!q||[n.name,n.category,n.feature,n.source?.path,n.details?.condition,n.details?.handler].join(' ').toLowerCase().includes(q)));document.getElementById('rows').innerHTML=list.slice(0,5000).map(makeRow).join('')||'<tr><td colspan="5" class="empty">No matching source nodes.</td></tr>';document.getElementById('tableCount').textContent=list.length+' results';document.querySelectorAll('[data-node]').forEach(b=>b.onclick=()=>{showView('graph');selectNode(b.dataset.node)})}
document.getElementById('tableSearch').oninput=renderRows;document.getElementById('search').oninput=()=>{document.getElementById('tableSearch').value=document.getElementById('search').value;renderRows()};document.getElementById('category').onchange=renderRows;document.getElementById('feature').onchange=renderRows;
function showView(name){view=name;document.querySelectorAll('.view').forEach(s=>s.classList.toggle('hidden',s.id!==name));document.querySelectorAll('.tab[data-view]').forEach(b=>b.classList.toggle('active',b.dataset.view===name))}document.querySelectorAll('.tab[data-view]').forEach(b=>b.onclick=()=>showView(b.dataset.view));
function selectNode(id){selected=byId.get(id);if(!selected)return;document.getElementById('selectedNode').textContent=selected.category+': '+selected.name;const links=data.edges.filter(e=>e.from===id||e.to===id).slice(0,40);const otherIds=[...new Set(links.map(e=>e.from===id?e.to:e.from))].slice(0,20);const svg=document.getElementById('svg');svg.replaceChildren();const NS='http://www.w3.org/2000/svg';const center={x:500,y:225};const all=[selected,...otherIds.map(x=>byId.get(x)).filter(Boolean)];const positions=new Map([[selected.id,center]]);all.slice(1).forEach((n,i)=>{const angle=2*Math.PI*i/Math.max(1,all.length-1)-Math.PI/2;positions.set(n.id,{x:center.x+Math.cos(angle)*340,y:center.y+Math.sin(angle)*170})});for(const e of links){const a=positions.get(e.from===id?e.from:e.from),b=positions.get(e.to===id?e.to:e.to);if(!a||!b)continue;const line=document.createElementNS(NS,'line');line.setAttribute('x1',a.x);line.setAttribute('y1',a.y);line.setAttribute('x2',b.x);line.setAttribute('y2',b.y);line.setAttribute('class','edge '+(e.confidence==='inferred'?'inferred':''));svg.append(line)}for(const n of all){const p=positions.get(n.id);const g=document.createElementNS(NS,'g');g.setAttribute('class','node '+(n.id===id?'selected ':'')+(n.risk.length?'risk':''));g.setAttribute('transform','translate('+(p.x-76)+','+(p.y-23)+')');g.onclick=()=>selectNode(n.id);const rect=document.createElementNS(NS,'rect');rect.setAttribute('width','152');rect.setAttribute('height','46');const t=document.createElementNS(NS,'text');t.setAttribute('x','76');t.setAttribute('y','18');t.setAttribute('text-anchor','middle');t.textContent=(n.category+': '+n.name).slice(0,25);const s=document.createElementNS(NS,'text');s.setAttribute('x','76');s.setAttribute('y','34');s.setAttribute('text-anchor','middle');s.textContent=n.source?n.source.path.split('/').slice(-2).join('/')+'#L'+n.source.line:'';g.append(rect,t,s);svg.append(g)}const src=selected.source?'<a class="evidence" href="'+sourceHref(selected.source)+'">'+esc(selected.source.path)+'#L'+selected.source.line+'</a>':'No source location';const edgeHtml=links.map(e=>{const other=byId.get(e.from===id?e.to:e.from);return '<div class="edge '+(e.confidence==='inferred'?'inferred':'')+'"><b>'+esc(e.type)+'</b> '+esc(e.label||'')+' '+(other?'<button class="tab" data-node="'+esc(other.id)+'">'+esc(other.name)+'</button>':'')+'<br>'+e.evidence.map(v=>'<a href="'+sourceHref(v)+'">'+esc(v.path)+'#L'+v.line+'</a>').join(', ')+'</div>'}).join('');document.getElementById('nodeDetail').innerHTML='<div><h3>'+esc(selected.name)+'</h3><span class="chip">'+esc(selected.category)+'</span><span class="chip">'+esc(selected.feature)+'</span><p>'+src+'</p><pre>'+esc(JSON.stringify(selected.details,null,2))+'</pre>'+selected.risk.map(r=>'<div class="note">'+esc(r)+'</div>').join('')+'</div><div><h3>Connected evidence ('+links.length+')</h3><div class="edges">'+(edgeHtml||'<div class="empty">No connected static edges found.</div>')+'</div></div>';document.querySelectorAll('#nodeDetail [data-node]').forEach(b=>b.onclick=()=>selectNode(b.dataset.node))}
document.getElementById('graphSearch').oninput=e=>{const q=e.target.value.toLowerCase();const n=data.nodes.find(item=>String(item.name??'').toLowerCase().includes(q)||String(item.id??'').toLowerCase().includes(q));if(n)selectNode(n.id)};
document.getElementById('diagramList').innerHTML=diagrams.map(d=>'<h3>'+esc(d.name)+'</h3><pre class="diagram">'+esc(d.text)+'</pre>').join('');document.getElementById('limits').innerHTML=data.limitations.map(v=>'<li>'+esc(v)+'</li>').join('');document.getElementById('unresolved').innerHTML=data.unresolved.map(u=>'<div class="edge inferred">'+esc(u.type)+': '+esc(u.note)+' '+(u.file?'<a href="'+sourceHref({path:u.file,line:u.line})+'">'+esc(u.file)+'#L'+u.line+'</a>':'')+'</div>').join('')||'<div class="empty">No unresolved references detected by configured patterns.</div>';document.getElementById('docVersions').innerHTML=data.documentationVersions.map(d=>{const node=data.nodes.find(n=>n.category==='documentation'&&n.source?.path===d.file);const label=d.current===true?'<span class="chip">matches release</span>':d.current===false?'<span class="chip risk">version differs</span>':'<span class="chip inferred">unversioned</span>';return '<div>'+(node?'<a href="'+sourceHref(node.source)+'">'+esc(d.file)+'#L'+node.source.line+'</a>':esc(d.file))+': '+esc(d.version||'no top-level version detected')+' '+label+'</div>'}).join('');document.getElementById('baselineStatus').textContent=JSON.stringify(data.baselineComparison);const cite=file=>{const node=data.nodes.find(n=>n.source?.path===file);return node?'<a href="'+sourceHref(node.source)+'">'+esc(file)+'#L'+node.source.line+'</a>':esc(file)};const reviewed=data.reviewedNotes||{};document.getElementById('reviewNotes').innerHTML='<h3>Verification notes</h3>'+((reviewed.verification||[]).map(v=>'<div class="edge '+(String(v.status).includes('failed')?'inferred':'')+'"><b>'+esc(v.scope)+'</b> · '+esc(v.result)+'<br><span class="sub">'+esc(v.command||'')+'</span></div>').join(''))+'<h3>Documentation and repository claims</h3>'+((reviewed.documentEvidence||[]).map(n=>'<div class="edge inferred"><b>'+esc(n.id)+'</b> '+esc(n.observation)+'<br>'+n.sources.map(cite).join(' · ')+'</div>').join(''));renderRows();
</script></body></html>`;
write('dashboard.html', dashboard);

console.log(JSON.stringify({ outputDir: path.relative(root, outputDir), counts, nodes: nodes.length, edges: edges.length, baseline: comparison.status, dirtyFiles: dirtyFiles.length }, null, 2));