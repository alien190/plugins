import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

/// Splash animation
class CameraSplash extends StatefulWidget {
  final TakePictureAnimationState _takePictureAnimation;

  /// Default constructor
  const CameraSplash({
    Key? key,
    required TakePictureAnimationState takePictureAnimation,
  })  : _takePictureAnimation = takePictureAnimation,
        super(key: key);

  @override
  _CameraSplashState createState() => _CameraSplashState();
}

class _CameraSplashState extends State<CameraSplash>
    with SingleTickerProviderStateMixin {
  TakePictureAnimationState _takePictureAnimation =
      TakePictureAnimationState.none;
  bool _isShown = false;
  late AnimationController _animationController;
  late Animation<int> _colorAnimationIn;
  late Animation<int> _colorAnimationOut;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    _animationController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 400),
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
    _handleAnimationState(widget._takePictureAnimation);
  }

  void _handleAnimationState(TakePictureAnimationState takePictureAnimation) {
    if (_takePictureAnimation.isInProgress &&
        takePictureAnimation.isStopped &&
        !_isShown) {
      _isShown = true;
      _takePictureAnimation = TakePictureAnimationState.stopped;
      _animationController.forward(from: 0).then((_) {
        _isShown = false;
        if (mounted) setState(() {});
      });
      if (mounted) setState(() {});
    }

    if (!_takePictureAnimation.isInProgress &&
        takePictureAnimation.isInProgress &&
        !_isShown) {
      _takePictureAnimation = TakePictureAnimationState.inProgress;
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
