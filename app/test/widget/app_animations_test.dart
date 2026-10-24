import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/core/design/app_animations.dart';

void main() {
  testWidgets(
    'optional animation presets are omitted when motion is disabled',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: Column(
                children: [
                  const Text('screen').screenEntry(),
                  const Text('list').listEntry(1),
                  const Text('success').successFlash(),
                  const Text('error').errorShake(),
                  const Text('sheet').frostedSlideUp(),
                  const Text('fade').arcticFade(),
                  const Text('bounce').impactBounce(),
                  const Text('stagger').glacialStagger(1),
                  const Text('pop').popIn(),
                  const Text('tab').tabEntry(),
                  const Text('press').pressable(),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.byType(Animate), findsNothing);
      for (final label in [
        'screen',
        'list',
        'success',
        'error',
        'sheet',
        'fade',
        'bounce',
        'stagger',
        'pop',
        'tab',
        'press',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
    },
  );

  testWidgets('animation presets remain active when motion is allowed', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: const Text('screen').screenEntry())),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Animate), findsOneWidget);
  });

  testWidgets('pressable action still works when motion is disabled', (
    tester,
  ) async {
    var tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: const Text('Tap me').pressable(onTap: () => tapped = true),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Tap me'));

    expect(tapped, isTrue);
  });

  testWidgets('pressable exposes a semantic tap action', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: const Text('Tap me').pressable(onTap: () {})),
        ),
      );

      expect(
        tester
            .getSemantics(find.byType(GestureDetector))
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue,
      );
    } finally {
      semantics.dispose();
    }
  });
}
