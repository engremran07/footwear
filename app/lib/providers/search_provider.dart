import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Global search query state shared by list screens.
final searchQueryProvider = StateProvider<String>((_) => '');
