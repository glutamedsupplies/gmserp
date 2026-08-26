import 'package:flutter/material.dart';

import 'compact_page.dart';

/// Client-side lazy paging for long in-memory lists.
///
/// Shows [pageSize] rows first, then reveals more as the user scrolls near
/// the bottom (or taps Load more).
class LazyListPager {
  LazyListPager({
    this.pageSize = 12,
    required this.onChanged,
  }) {
    visibleCount = pageSize;
    scrollController.addListener(_onScroll);
  }

  final int pageSize;
  final VoidCallback onChanged;

  final ScrollController scrollController = ScrollController();

  late int visibleCount;
  bool loadingMore = false;
  int _lastTotal = 0;

  bool hasMore([int? total]) => visibleCount < (total ?? _lastTotal);

  List<T> takeVisible<T>(List<T> items) {
    _lastTotal = items.length;
    final count = visibleCount.clamp(0, items.length);
    return items.take(count).toList();
  }

  void reset() {
    visibleCount = pageSize;
    loadingMore = false;
  }

  void loadMore([int? total]) {
    final max = total ?? _lastTotal;
    if (loadingMore || visibleCount >= max) return;
    loadingMore = true;
    visibleCount = (visibleCount + pageSize).clamp(0, max);
    onChanged();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      loadingMore = false;
      onChanged();
    });
  }

  void _onScroll() {
    if (!scrollController.hasClients || loadingMore) return;
    final position = scrollController.position;
    if (position.pixels < position.maxScrollExtent - 240) return;
    loadMore();
  }

  void dispose() {
    scrollController.removeListener(_onScroll);
    scrollController.dispose();
  }
}

/// Footer shown under a lazily paged list.
class LazyListFooter extends StatelessWidget {
  const LazyListFooter({
    super.key,
    required this.hasMore,
    required this.remaining,
    required this.loadingMore,
    required this.onLoadMore,
  });

  final bool hasMore;
  final int remaining;
  final bool loadingMore;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    if (!hasMore && !loadingMore) return const SizedBox.shrink();
    final density = CompactPageStyle.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: density.compact ? 12 : 16),
      child: Center(
        child: loadingMore
            ? SizedBox(
                width: density.compact ? 20 : 22,
                height: density.compact ? 20 : 22,
                child: const CircularProgressIndicator(strokeWidth: 2),
              )
            : TextButton(
                onPressed: onLoadMore,
                child: Text(
                  remaining > 0
                      ? 'Load more ($remaining left)'
                      : 'Load more',
                ),
              ),
      ),
    );
  }
}
