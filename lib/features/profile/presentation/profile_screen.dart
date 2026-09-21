import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/state_message.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import 'user_profile_screen.dart';

/// Вкладка «Профиль» — тот же экран, что и профиль любого человека, но
/// открытый на себя: одна модель и один экран, отличаются только действия.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserProvider);
    if (me == null) return const LoadingView();
    return UserProfileScreen(userId: me.id, embedded: true);
  }
}
