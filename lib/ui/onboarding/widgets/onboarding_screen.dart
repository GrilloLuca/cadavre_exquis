import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:cadavre_exquisite/data/repositories/onboarding/onboarding_repository.dart';
import 'package:cadavre_exquisite/l10n/app_localizations.dart';
import 'package:cadavre_exquisite/ui/core/themes/app_colors.dart';
import 'package:cadavre_exquisite/ui/onboarding/view_models/onboarding_view_model.dart';

/// Full-screen slides explaining the game, shown by `AuthWrapper` on the
/// first launch. Each slide is a small animated demo of one step of a game
/// (four authors, the five visible words, the reveal) with a short title
/// under it, so the rules can be understood without reading. Skipping or
/// finishing the slides marks them seen, and `AuthWrapper` moves on by
/// itself. Creates its [OnboardingViewModel] once, in `initState`.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const _pageCount = 3;

  late final OnboardingViewModel _viewModel;
  final _pageController = PageController();
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _viewModel = OnboardingViewModel(
      onboardingRepository: context.read<OnboardingRepository>(),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    _viewModel.dispose();
    super.dispose();
  }

  void _next() {
    _pageController.nextPage(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isLast = _page == _pageCount - 1;
    return Scaffold(
      backgroundColor: AppColors.sage,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Visibility(
                visible: !isLast,
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                child: TextButton(
                  onPressed: _viewModel.complete.execute,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primaryDark,
                  ),
                  child: Text(l10n.onboardingSkip),
                ),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (page) => setState(() => _page = page),
                children: [
                  _Slide(
                    title: l10n.onboardingTitle1,
                    body: l10n.onboardingBody1,
                    illustration: _Animated(
                      active: _page == 0,
                      duration: const Duration(milliseconds: 1600),
                      builder: (t) => _AuthorsIllustration(t: t),
                    ),
                  ),
                  _Slide(
                    title: l10n.onboardingTitle2,
                    body: l10n.onboardingBody2,
                    illustration: _Animated(
                      active: _page == 1,
                      duration: const Duration(milliseconds: 2800),
                      builder: (t) => _PeekIllustration(
                        t: t,
                        visibleWords: l10n.onboardingDemoVisible,
                        continuation: l10n.onboardingDemoPart2,
                      ),
                    ),
                  ),
                  _Slide(
                    title: l10n.onboardingTitle3,
                    body: l10n.onboardingBody3,
                    illustration: _Animated(
                      active: _page == 2,
                      duration: const Duration(milliseconds: 2400),
                      builder: (t) => _RevealIllustration(
                        t: t,
                        parts: [
                          '${l10n.onboardingDemoHidden} '
                              '${l10n.onboardingDemoVisible}',
                          l10n.onboardingDemoPart2,
                          l10n.onboardingDemoPart3,
                          l10n.onboardingDemoPart4,
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            _Dots(count: _pageCount, current: _page),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton(
                  onPressed: isLast ? _viewModel.complete.execute : _next,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.cream,
                    shape: const StadiumBorder(),
                    textStyle: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: Text(
                    isLast ? l10n.onboardingStart : l10n.onboardingNext,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One colour per author of the demo story, in writing order.
const _authorColors = [
  AppColors.primaryDark,
  Color(0xFFC4704F),
  Color(0xFFD9A441),
  Color(0xFF4F7186),
];

/// How far a step that runs between [begin] and [end] of the whole
/// animation has got at [t], eased.
double _stage(double t, double begin, double end) => Curves.easeOutCubic
    .transform(((t - begin) / (end - begin)).clamp(0.0, 1.0));

/// One page: the illustration over a big title and a single line of
/// explanation, centred together. The illustration takes about half the
/// height and is scaled down to fit it; if the page is still too short
/// (small phone in landscape, very large text) it scrolls instead of
/// overflowing.
class _Slide extends StatelessWidget {
  const _Slide({
    required this.title,
    required this.body,
    required this.illustration,
  });

  final String title;
  final String body;
  final Widget illustration;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                height: (constraints.maxHeight * 0.55).clamp(110.0, 340.0),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: SizedBox(
                      width: 300,
                      child: ExcludeSemantics(child: illustration),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.ink,
                  fontSize: 30,
                  height: 1.15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                body,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.ink.withValues(alpha: 0.75),
                  fontSize: 16,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

/// Plays a one-shot animation each time its page becomes the [active] one
/// and hands the progress (0 to 1) to [builder]. With animations disabled
/// in the system settings it shows the final frame at once.
class _Animated extends StatefulWidget {
  const _Animated({
    required this.active,
    required this.duration,
    required this.builder,
  });

  final bool active;
  final Duration duration;
  final Widget Function(double t) builder;

  @override
  State<_Animated> createState() => _AnimatedState();
}

class _AnimatedState extends State<_Animated>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    if (widget.active) _controller.forward();
  }

  @override
  void didUpdateWidget(_Animated oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return widget.builder(1);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => widget.builder(_controller.value),
    );
  }
}

/// Slide 1: four authors, each with their own strip of paper, arriving one
/// after the other.
class _AuthorsIllustration extends StatelessWidget {
  const _AuthorsIllustration({required this.t});

  final double t;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < _authorColors.length; i++)
          _buildStrip(i, _stage(t, i * 0.2, i * 0.2 + 0.4)),
      ],
    );
  }

  Widget _buildStrip(int index, double progress) {
    final fromLeft = index.isEven;
    return Opacity(
      opacity: progress,
      child: Transform.translate(
        offset: Offset((1 - progress) * (fromLeft ? -48 : 48), 0),
        child: Transform.rotate(
          angle: fromLeft ? -0.018 : 0.018,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                _Avatar(color: _authorColors[index], size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: _Paper(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Column(
                      children: [
                        const _Bar(widthFactor: 1),
                        const SizedBox(height: 8),
                        _Bar(widthFactor: 0.5 + 0.1 * ((index * 3) % 4)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Slide 2: the previous part is hidden except for its last five words,
/// which light up; then the next author types on from them.
class _PeekIllustration extends StatelessWidget {
  const _PeekIllustration({
    required this.t,
    required this.visibleWords,
    required this.continuation,
  });

  final double t;
  final String visibleWords;
  final String continuation;

  static const _textStyle = TextStyle(
    color: AppColors.ink,
    fontSize: 17,
    height: 1.3,
  );

  @override
  Widget build(BuildContext context) {
    final highlight = _stage(t, 0.1, 0.4);
    final typed = ((t - 0.5) / 0.45).clamp(0.0, 1.0);
    final characters = continuation.characters;
    final typedText =
        characters.take((characters.length * typed).round()).toString();

    return _Paper(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _Avatar(color: _authorColors[0], size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const Column(
                      children: [
                        _Bar(widthFactor: 1),
                        SizedBox(height: 8),
                        _Bar(widthFactor: 1),
                        SizedBox(height: 8),
                        _Bar(widthFactor: 0.7),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        color: AppColors.cream,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.visibility_off_outlined,
                        size: 22,
                        color: AppColors.ink,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 38),
            child: Transform.scale(
              scale: 0.85 + 0.15 * highlight,
              alignment: AlignmentDirectional.centerStart
                  .resolve(Directionality.of(context)),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Color.lerp(
                    AppColors.cream,
                    _authorColors[2].withValues(alpha: 0.45),
                    highlight,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '… $visibleWords',
                  style: _textStyle.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Divider(
              height: 1,
              color: AppColors.ink.withValues(alpha: 0.12),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Avatar(color: _authorColors[1], size: 28),
              const SizedBox(width: 10),
              Expanded(
                // The invisible full text keeps the paper from growing
                // while the visible one is typed.
                child: Stack(
                  children: [
                    Opacity(
                      opacity: 0,
                      child: Text('$continuation  ', style: _textStyle),
                    ),
                    Text.rich(
                      TextSpan(
                        text: typedText,
                        children: [
                          WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: Container(
                              width: 2,
                              height: 18,
                              margin: const EdgeInsets.only(left: 2),
                              color: _authorColors[1],
                            ),
                          ),
                        ],
                      ),
                      style: _textStyle,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Slide 3: the four hidden parts turn into text one after the other, and
/// read as one story.
class _RevealIllustration extends StatelessWidget {
  const _RevealIllustration({required this.t, required this.parts});

  final double t;
  final List<String> parts;

  @override
  Widget build(BuildContext context) {
    final sparkle = _stage(t, 0.8, 1);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        _Paper(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < parts.length; i++)
                Padding(
                  padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
                  child: _buildPart(i, _stage(t, i * 0.2, i * 0.2 + 0.3)),
                ),
            ],
          ),
        ),
        PositionedDirectional(
          top: -14,
          end: -10,
          child: Transform.scale(
            scale: sparkle,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _authorColors[2],
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.auto_awesome,
                size: 22,
                color: AppColors.cream,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPart(int index, double revealed) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Avatar(color: _authorColors[index], size: 24),
        const SizedBox(width: 10),
        Expanded(
          child: Stack(
            children: [
              Opacity(
                opacity: revealed,
                child: Text(
                  parts[index],
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 16,
                    height: 1.3,
                  ),
                ),
              ),
              Positioned.fill(
                child: Opacity(
                  opacity: 1 - revealed,
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _Bar(widthFactor: 1),
                      _Bar(widthFactor: 0.75),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A sheet of cream paper.
class _Paper extends StatelessWidget {
  const _Paper({required this.child, required this.padding});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.cream,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.ink.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: AppColors.ink.withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// A line of writing that can't be read.
class _Bar extends StatelessWidget {
  const _Bar({required this.widthFactor});

  final double widthFactor;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: widthFactor,
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        height: 8,
        decoration: BoxDecoration(
          color: AppColors.ink.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }
}

/// The round badge standing for one author.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Icon(Icons.person, size: size * 0.65, color: AppColors.cream),
    );
  }
}

/// The page indicator: the current page's dot is a wider pill.
class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.current});

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: i == current ? 26 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: i == current ? AppColors.primary : AppColors.cream,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
      ],
    );
  }
}
