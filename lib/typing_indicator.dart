import 'package:flutter/material.dart';

/// Small animated "someone is typing" indicator: three dots bouncing in
/// sequence, shown next to stories another user currently has locked.
class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key});

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32.0,
      height: 24.0,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(3, (index) {
              final t = (_controller.value - index * 0.2) % 1.0;
              final bounce = t < 0.5 ? t * 2 : (1 - t) * 2;
              return Transform.translate(
                offset: Offset(0, -4.0 * bounce),
                child: const CircleAvatar(
                  radius: 3.5,
                  backgroundColor: Colors.black45,
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
