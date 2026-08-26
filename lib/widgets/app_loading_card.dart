import 'package:flutter/material.dart';

import 'feedback_card.dart';

/// Page / list loading card — same visual language as overlay spinners.
class AppLoadingCard extends StatelessWidget {
  const AppLoadingCard({
    super.key,
    this.title = 'Loading',
    this.message = 'Please wait…',
    this.compact = false,
  });

  final String title;
  final String message;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return AppFeedbackCard(
      kind: FeedbackKind.loading,
      title: title,
      message: message,
      compact: compact,
    );
  }
}

/// Centered loading state for full pages / auth gate.
class AppLoadingView extends StatelessWidget {
  const AppLoadingView({
    super.key,
    this.title = 'Loading',
    this.message = 'Please wait…',
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: AppLoadingCard(title: title, message: message),
        ),
      ),
    );
  }
}
