import 'package:flutter/material.dart';

/// Splash animation
class CameraSplash extends StatefulWidget {
  final bool _isShown;

  /// Default constructor
  const CameraSplash({Key? key, required bool isShown})
      : _isShown = isShown,
        super(key: key);

  @override
  _CameraSplashState createState() => _CameraSplashState();
}

class _CameraSplashState extends State<CameraSplash>
    with SingleTickerProviderStateMixin {
  bool _isShown = false;
  late AnimationController _animationController;
  late Animation<int> _colorAnimationIn;
  late Animation<int> _colorAnimationOut;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    _animationController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 300),
    );

    _colorAnimationIn = IntTween(begin: 0, end: 255).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Interval(
          0,
          0.3,
          curve: Curves.easeOutCirc,
        ),
      ),
    );

    _colorAnimationOut = IntTween(begin: 0, end: 150).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Interval(
          0.3,
          0.5,
          curve: Curves.easeInCirc,
        ),
      ),
    );

    _scaleAnimation = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Interval(
          0.3,
          1,
          curve: Curves.easeInQuad,
        ),
      ),
    );

    super.initState();
  }

  @override
  void didUpdateWidget(covariant CameraSplash oldWidget) {
    super.didUpdateWidget(oldWidget);
    _showSplash(widget._isShown);
  }

  void _showSplash(bool isShown) {
    if (!_isShown && isShown) {
      _isShown = true;
      _animationController.forward(from: 0).then((_) {
        _isShown = false;
        if (mounted) setState(() {});
      });
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return _isShown
        ? AnimatedBuilder(
            animation: _animationController,
            builder: (_, __) {
              final int _colorValue =
                  _colorAnimationIn.value - _colorAnimationOut.value;
              return Transform.scale(
                alignment: Alignment.bottomRight,
                scale: _scaleAnimation.value,
                child: Container(
                  color: Color.fromARGB(
                    _colorValue,
                    _colorValue,
                    _colorValue,
                    _colorValue,
                  ),
                ),
              );
            },
          )
        : Container(color: Colors.transparent);
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }
}
//return _isShown
//     ? TweenAnimationBuilder<int>(
//         tween: IntTween(begin: 0, end: 255),
//         duration: Duration(milliseconds: 300),
//         curve: Curves.easeOutCirc,
//         builder: (_, int value, __) => Container(
//           color: Color.fromARGB(value, value, value, value),
//         ),
//         onEnd: () {
//           _isShown = false;
//           if (mounted) setState(() {});
//         },
//       )
//     : Container(color: Colors.transparent);
