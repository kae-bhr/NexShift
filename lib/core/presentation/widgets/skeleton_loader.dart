import 'package:flutter/material.dart';
import 'package:nexshift_app/core/utils/design_system.dart';

/// Skeleton loader avec effet shimmer
class SkeletonLoader extends StatefulWidget {
  final double? width;
  final double height;
  final BorderRadius? borderRadius;

  const SkeletonLoader({
    super.key,
    this.width,
    required this.height,
    this.borderRadius,
  });

  @override
  State<SkeletonLoader> createState() => _SkeletonLoaderState();
}

class _SkeletonLoaderState extends State<SkeletonLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();
    _animation = Tween<double>(
      begin: -2,
      end: 2,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.grey[800]! : Colors.grey[300]!;
    final highlightColor = isDark ? Colors.grey[700]! : Colors.grey[100]!;

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius ?? KBorderRadius.circularM,
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [baseColor, highlightColor, baseColor],
              stops: const [0.0, 0.5, 1.0],
              transform: GradientRotation(_animation.value),
            ),
          ),
        );
      },
    );
  }
}

/// Skeleton pour une carte de liste (ex: agent dans TeamPage)
class SkeletonListTile extends StatelessWidget {
  const SkeletonListTile({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.symmetric(vertical: KSpacing.s / 2),
      elevation: KElevation.low,
      shape: RoundedRectangleBorder(borderRadius: KBorderRadius.circularM),
      child: Padding(
        padding: KSpacing.paddingL,
        child: Row(
          children: [
            SkeletonLoader(
              width: KAvatarSize.m,
              height: KAvatarSize.m,
              borderRadius: BorderRadius.circular(KAvatarSize.m),
            ),
            SizedBox(width: KSpacing.l),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonLoader(
                    width: 150,
                    height: 16,
                    borderRadius: KBorderRadius.circularS,
                  ),
                  SizedBox(height: KSpacing.s),
                  SkeletonLoader(
                    width: 80,
                    height: 12,
                    borderRadius: KBorderRadius.circularS,
                  ),
                ],
              ),
            ),
            SkeletonLoader(
              width: 24,
              height: 24,
              borderRadius: KBorderRadius.circularS,
            ),
          ],
        ),
      ),
    );
  }
}

/// Skeleton pour une carte de compétence
class SkeletonSkillCard extends StatelessWidget {
  const SkeletonSkillCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.only(bottom: KSpacing.m),
      elevation: KElevation.medium,
      shape: RoundedRectangleBorder(borderRadius: KBorderRadius.circularM),
      child: Padding(
        padding: KSpacing.paddingL,
        child: Row(
          children: [
            SkeletonLoader(
              width: 50,
              height: 50,
              borderRadius: BorderRadius.circular(25),
            ),
            SizedBox(width: KSpacing.l),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonLoader(
                    width: 100,
                    height: 18,
                    borderRadius: KBorderRadius.circularS,
                  ),
                  SizedBox(height: KSpacing.s),
                  SkeletonLoader(
                    width: 120,
                    height: 13,
                    borderRadius: KBorderRadius.circularS,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Liste de skeletons pour TeamPage
class TeamPageSkeleton extends StatelessWidget {
  const TeamPageSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: KSpacing.paddingL,
      children: [
        // Section header skeleton
        Row(
          children: [
            SkeletonLoader(
              width: 18,
              height: 18,
              borderRadius: BorderRadius.circular(9),
            ),
            SizedBox(width: KSpacing.s),
            SkeletonLoader(
              width: 120,
              height: 16,
              borderRadius: KBorderRadius.circularS,
            ),
            SizedBox(width: KSpacing.s),
            Expanded(
              child: SkeletonLoader(height: 1, borderRadius: BorderRadius.zero),
            ),
          ],
        ),
        SizedBox(height: KSpacing.s),
        const SkeletonListTile(),
        const SkeletonListTile(),
        SizedBox(height: KSpacing.l),
        // Second section
        Row(
          children: [
            SkeletonLoader(
              width: 18,
              height: 18,
              borderRadius: BorderRadius.circular(9),
            ),
            SizedBox(width: KSpacing.s),
            SkeletonLoader(
              width: 80,
              height: 16,
              borderRadius: KBorderRadius.circularS,
            ),
            SizedBox(width: KSpacing.s),
            Expanded(
              child: SkeletonLoader(height: 1, borderRadius: BorderRadius.zero),
            ),
          ],
        ),
        SizedBox(height: KSpacing.s),
        ...List.generate(4, (_) => const SkeletonListTile()),
      ],
    );
  }
}

/// Liste de skeletons pour SkillsPage
class SkillsPageSkeleton extends StatelessWidget {
  const SkillsPageSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: KSpacing.paddingL,
      children: List.generate(5, (_) => const SkeletonSkillCard()),
    );
  }
}
