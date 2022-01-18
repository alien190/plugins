import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

/// Take picture animation widget
class CameraTakePictureAnimation extends StatefulWidget {
  /// Default constructor
  const CameraTakePictureAnimation({Key? key}) : super(key: key);

  @override
  State<CameraTakePictureAnimation> createState() =>
      _CameraTakePictureAnimationState();
}

class _CameraTakePictureAnimationState extends State<CameraTakePictureAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    _animationController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 800),
    );

    _scaleAnimation = Tween<double>(begin: 1.5, end: 1).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.elasticOut,
      ),
    );
    WidgetsBinding.instance
        ?.addPostFrameCallback((_) => _animationController.forward());
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (_, Widget? child) => Transform.scale(
          scale: _scaleAnimation.value,
          child: child,
        ),
        child: FittedBox(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.all(Radius.circular(3)),
              border: Border.all(
                width: 3,
                color: Colors.green,
              ),
            ),
            padding: EdgeInsets.symmetric(
              vertical: 10,
              horizontal: 15,
            ),
            child: Center(
              child: Text(
                'SAVE',
                style: TextStyle(
                  fontSize: 20,
                  color: Colors.white,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
