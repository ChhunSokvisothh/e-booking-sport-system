import 'package:flutter/material.dart';

/// Keeps page content readable and consistently centered on wide screens.
///
/// The child receives a MediaQuery width matching the constrained content
/// width, so responsive layouts calculate breakpoints from the page itself
/// rather than the full browser window.
class AppPageFrame extends StatelessWidget {
  const AppPageFrame({
    super.key,
    required this.child,
    this.maxWidth = 1040,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screen = MediaQuery.of(context);
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : screen.size.width;
        final contentWidth = availableWidth.clamp(0.0, maxWidth).toDouble();

        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: contentWidth,
            height: constraints.maxHeight.isFinite
                ? constraints.maxHeight
                : null,
            child: MediaQuery(
              data: screen.copyWith(
                size: Size(contentWidth, screen.size.height),
              ),
              child: child,
            ),
          ),
        );
      },
    );
  }
}
