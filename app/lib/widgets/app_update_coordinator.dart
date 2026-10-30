import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_brand.dart';
import '../core/l10n/app_locale.dart';
import '../core/services/app_update_service.dart';
import '../core/utils/app_update_policy.dart';
import '../core/utils/snack_helper.dart';

class AppUpdateCoordinator extends ConsumerStatefulWidget {
  const AppUpdateCoordinator({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<AppUpdateCoordinator> createState() =>
      _AppUpdateCoordinatorState();
}

class _AppUpdateCoordinatorState extends ConsumerState<AppUpdateCoordinator> {
  late final AppUpdateGateway _gateway;
  AppLifecycleListener? _lifecycleListener;
  StreamSubscription<AppUpdateInstallStatus>? _installStatusSubscription;
  AppUpdateDecision? _decision;
  bool _checking = false;
  bool _requiredUpdate = false;
  bool _optionalPromptShown = false;
  bool _actionInProgress = false;
  bool _completingFlexibleUpdate = false;
  String? _errorKey;

  String _text(String key) => trRead(key, ref.read(appLocaleProvider));

  @override
  void initState() {
    super.initState();
    _gateway = ref.read(appUpdateGatewayProvider);
    if (!_gateway.isSupported) return;

    _lifecycleListener = AppLifecycleListener(onResume: _checkForUpdate);
    _installStatusSubscription = _gateway.installUpdateListener.listen(
      _onInstallUpdateStatus,
      onError: (Object error, StackTrace stackTrace) {
        recordAppUpdateError(
          error,
          stackTrace,
          'Google Play update status listener failed.',
        );
      },
    );
    unawaited(_checkForUpdate());
  }

  @override
  void dispose() {
    _lifecycleListener?.dispose();
    unawaited(_installStatusSubscription?.cancel());
    super.dispose();
  }

  Future<void> _checkForUpdate() async {
    if (_checking || !_gateway.isSupported) return;
    setState(() {
      _checking = true;
      _errorKey = null;
    });

    try {
      final minimumVersionCode = await _gateway
          .fetchMinimumSupportedVersionCode();
      AppUpdateSnapshot? snapshot;
      try {
        snapshot = await _gateway.checkForUpdate();
      } on PlatformException catch (error, stackTrace) {
        recordAppUpdateError(
          error,
          stackTrace,
          'Google Play update check failed.',
        );
      } on MissingPluginException catch (error, stackTrace) {
        recordAppUpdateError(
          error,
          stackTrace,
          'Google Play update plugin is unavailable.',
        );
      }

      if (!mounted) return;
      final decision = AppUpdatePolicy.evaluate(
        currentVersionCode: AppBrand.androidVersionCode,
        minimumSupportedVersionCode: minimumVersionCode,
        updateAvailable: snapshot?.updateAvailable ?? false,
        availableVersionCode: snapshot?.availableVersionCode,
        updatePriority: snapshot?.updatePriority ?? 0,
        flexibleUpdateAllowed: snapshot?.flexibleUpdateAllowed ?? false,
        immediateUpdateAllowed: snapshot?.immediateUpdateAllowed ?? false,
        immediateUpdateInProgress: snapshot?.immediateUpdateInProgress ?? false,
      );
      setState(() {
        _decision = decision;
        _requiredUpdate = decision.isRequired;
      });

      if (snapshot?.flexibleUpdateDownloaded == true) {
        await _completeFlexibleUpdate();
      }

      if (decision.canStartImmediateUpdate ||
          (decision.isRequired &&
              snapshot?.immediateUpdateInProgress == true)) {
        await _startRequiredUpdate();
      } else if (decision.hasOptionalUpdate && !_optionalPromptShown) {
        _optionalPromptShown = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(_showOptionalUpdatePrompt());
        });
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  void _onInstallUpdateStatus(AppUpdateInstallStatus status) {
    if (status == AppUpdateInstallStatus.downloaded) {
      unawaited(_completeFlexibleUpdate());
    }
  }

  Future<void> _startRequiredUpdate() async {
    if (_actionInProgress) return;
    setState(() {
      _actionInProgress = true;
      _errorKey = null;
    });
    try {
      final result = await _gateway.performImmediateUpdate();
      if (!mounted) return;
      if (result != AppUpdateActionResult.success) {
        setState(() {
          _errorKey = result == AppUpdateActionResult.userCancelled
              ? 'app_update_required_cancelled'
              : 'app_update_failed';
        });
      }
    } on PlatformException catch (error, stackTrace) {
      recordAppUpdateError(error, stackTrace, 'Immediate app update failed.');
      if (mounted) setState(() => _errorKey = 'app_update_failed');
    } on MissingPluginException catch (error, stackTrace) {
      recordAppUpdateError(
        error,
        stackTrace,
        'Immediate update plugin missing.',
      );
      if (mounted) setState(() => _errorKey = 'app_update_failed');
    } finally {
      if (mounted) setState(() => _actionInProgress = false);
    }
  }

  Future<void> _startOptionalUpdate() async {
    try {
      if (_decision?.canStartFlexibleUpdate == true) {
        final result = await _gateway.startFlexibleUpdate();
        if (result == AppUpdateActionResult.failed) {
          _showUpdateError('app_update_failed');
        }
        return;
      }

      if (!await _gateway.openStoreListing()) {
        _showUpdateError('app_update_store_unavailable');
      }
    } on PlatformException catch (error, stackTrace) {
      recordAppUpdateError(error, stackTrace, 'Optional app update failed.');
      _showUpdateError('app_update_failed');
    } on MissingPluginException catch (error, stackTrace) {
      recordAppUpdateError(
        error,
        stackTrace,
        'Optional update plugin missing.',
      );
      _showUpdateError('app_update_failed');
    }
  }

  Future<void> _completeFlexibleUpdate() async {
    if (_completingFlexibleUpdate) return;
    _completingFlexibleUpdate = true;
    try {
      await _gateway.completeFlexibleUpdate();
    } on PlatformException catch (error, stackTrace) {
      recordAppUpdateError(
        error,
        stackTrace,
        'Downloaded flexible update could not be installed.',
      );
      _showUpdateError('app_update_failed');
    } on MissingPluginException catch (error, stackTrace) {
      recordAppUpdateError(
        error,
        stackTrace,
        'Flexible update installer plugin is missing.',
      );
      _showUpdateError('app_update_failed');
    } finally {
      _completingFlexibleUpdate = false;
    }
  }

  Future<void> _openStoreListing() async {
    setState(() {
      _actionInProgress = true;
      _errorKey = null;
    });
    try {
      if (!await _gateway.openStoreListing() && mounted) {
        setState(() => _errorKey = 'app_update_store_unavailable');
      }
    } on PlatformException catch (error, stackTrace) {
      recordAppUpdateError(
        error,
        stackTrace,
        'Could not open Play Store listing.',
      );
      if (mounted) setState(() => _errorKey = 'app_update_store_unavailable');
    } on MissingPluginException catch (error, stackTrace) {
      recordAppUpdateError(
        error,
        stackTrace,
        'Store launcher plugin is missing.',
      );
      if (mounted) setState(() => _errorKey = 'app_update_store_unavailable');
    } finally {
      if (mounted) setState(() => _actionInProgress = false);
    }
  }

  void _showUpdateError(String key) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(errorSnackBar(_text(key)));
  }

  Future<void> _showOptionalUpdatePrompt() async {
    if (!mounted || _decision?.hasOptionalUpdate != true) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_text('app_update_available_title')),
        content: Text(_text('app_update_available_message')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(_text('app_update_later')),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              unawaited(_startOptionalUpdate());
            },
            child: Text(_text('app_update_now')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_gateway.isSupported || !_requiredUpdate) return widget.child;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.system_update_alt,
                    size: 52,
                    color: colors.primary,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _text('app_update_required_title'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _text('app_update_required_message'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  if (_errorKey != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _text(_errorKey!),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(color: colors.error),
                    ),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _actionInProgress ? null : _openStoreListing,
                      icon: const Icon(Icons.open_in_new),
                      label: Text(_text('app_update_open_store')),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _checking || _actionInProgress
                          ? null
                          : _checkForUpdate,
                      icon: _checking
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh),
                      label: Text(_text('app_update_retry')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
