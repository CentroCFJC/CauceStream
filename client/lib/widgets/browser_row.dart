import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/browser_item.dart';
import 'browser_card.dart';

class BrowserRow extends StatefulWidget {
  final String title;
  final List<BrowserItem> items;
  final bool initialFocus;
  final List<FocusNode>? focusNodes;
  final List<VoidCallback?>? upCallbacks;
  final List<VoidCallback?>? downCallbacks;
  final ScrollController? scrollController;
  final ValueChanged<BrowserItem>? onItemSelected;

  const BrowserRow({
    super.key,
    required this.title,
    required this.items,
    this.initialFocus = false,
    this.focusNodes,
    this.upCallbacks,
    this.downCallbacks,
    this.scrollController,
    this.onItemSelected,
  });

  @override
  State<BrowserRow> createState() => _BrowserRowState();
}

class _BrowserRowState extends State<BrowserRow> {
  double _cardWidth(BuildContext context) {
    return MediaQuery.of(context).size.height * 0.16;
  }

  void _scrollToCenter(int index, ScrollController controller, BuildContext context) {
    if (!controller.hasClients || !controller.position.hasContentDimensions) return;
    final double itemWidth = _cardWidth(context) + 16;
    final double paddingStart = MediaQuery.of(context).size.width * 0.015;
    final double viewportWidth = controller.position.viewportDimension;
    if (viewportWidth <= 0) return;

    final double itemCenter = paddingStart + (index * itemWidth) + (itemWidth / 2);
    final double targetOffset = itemCenter - (viewportWidth / 2);

    final double clampedOffset = targetOffset.clamp(
      0.0,
      controller.position.maxScrollExtent,
    );

    if ((clampedOffset - controller.offset).abs() < 1.0) return;

    controller.animateTo(
      clampedOffset,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOutQuad,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.scrollController;
    final sh = MediaQuery.of(context).size.height;
    final cardH = _cardWidth(context) * 1.35 + 6;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(sh * 0.025, sh * 0.012, 0, sh * 0.008),
          child: Text(
            widget.title,
            style: TextStyle(
              color: Colors.white,
              fontSize: sh * 0.026,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        SizedBox(
          height: cardH,
          child: Stack(
            children: [
              ListView(
                controller: ctrl,
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.hardEdge,
                padding: EdgeInsets.symmetric(horizontal: MediaQuery.of(context).size.width * 0.015),
                children: widget.items.asMap().entries.map((e) {
                  final item = e.value;
                  final index = e.key;

                  VoidCallback? onLeft;
                  if (index > 0 && widget.focusNodes != null && index < widget.focusNodes!.length) {
                    final prevNode = widget.focusNodes![index - 1];
                    onLeft = () => prevNode.requestFocus();
                  }

                  VoidCallback? onRight;
                  if (index < widget.items.length - 1 &&
                      widget.focusNodes != null &&
                      index + 1 < widget.focusNodes!.length) {
                    final nextNode = widget.focusNodes![index + 1];
                    onRight = () => nextNode.requestFocus();
                  }

                  return _FocusableBrowserCard(
                    key: ValueKey('${widget.title}_$index'),
                    item: item,
                    onSelected: widget.onItemSelected != null
                        ? () => widget.onItemSelected!(item)
                        : null,
                    autofocus: widget.initialFocus && index == 0,
                    focusNode: widget.focusNodes != null && index < widget.focusNodes!.length
                        ? widget.focusNodes![index]
                        : null,
                    onFocus: () {
                      if (ctrl != null) {
                        _scrollToCenter(index, ctrl, context);
                      }
                    },
                    onUp: widget.upCallbacks != null && index < widget.upCallbacks!.length
                        ? widget.upCallbacks![index]
                        : null,
                    onDown: widget.downCallbacks != null && index < widget.downCallbacks!.length
                        ? widget.downCallbacks![index]
                        : null,
                    onLeft: onLeft,
                    onRight: onRight,
                    isFirst: index == 0,
                    isLast: index == widget.items.length - 1,
                  );
                }).toList(),
              ),
              if (ctrl != null) ...[
                _buildEdgeGradient(ctrl, isLeft: true),
                _buildEdgeGradient(ctrl, isLeft: false),
              ],
            ],
          ),
        ),
        SizedBox(height: MediaQuery.of(context).size.height * 0.015),
      ],
    );
  }

  Widget _buildEdgeGradient(ScrollController ctrl, {required bool isLeft}) {
    return Positioned(
      left: isLeft ? 0 : null,
      right: isLeft ? null : 0,
      top: 0,
      bottom: 0,
      width: MediaQuery.of(context).size.width * 0.04,
      child: IgnorePointer(
        child: ListenableBuilder(
          listenable: ctrl,
          builder: (context, _) {
            final show = isLeft
                ? ctrl.hasClients && ctrl.position.hasContentDimensions && ctrl.offset > 0
                : ctrl.hasClients && ctrl.position.hasContentDimensions && ctrl.offset < ctrl.position.maxScrollExtent;
            return AnimatedOpacity(
              opacity: show ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: isLeft ? Alignment.centerLeft : Alignment.centerRight,
                    end: isLeft ? Alignment.centerRight : Alignment.centerLeft,
                    colors: [
                      const Color(0xFF0A1628).withAlpha(230),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _FocusableBrowserCard extends StatefulWidget {
  final BrowserItem item;
  final VoidCallback? onSelected;
  final bool autofocus;
  final FocusNode? focusNode;
  final VoidCallback? onFocus;
  final VoidCallback? onUp;
  final VoidCallback? onDown;
  final VoidCallback? onLeft;
  final VoidCallback? onRight;
  final bool isFirst;
  final bool isLast;

  const _FocusableBrowserCard({
    super.key,
    required this.item,
    this.onSelected,
    this.autofocus = false,
    this.focusNode,
    this.onFocus,
    this.onUp,
    this.onDown,
    this.onLeft,
    this.onRight,
    this.isFirst = false,
    this.isLast = false,
  });

  @override
  State<_FocusableBrowserCard> createState() => _FocusableBrowserCardState();
}

class _FocusableBrowserCardState extends State<_FocusableBrowserCard> {
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _isFocused = widget.focusNode?.hasFocus ?? false;
  }

  @override
  void didUpdateWidget(_FocusableBrowserCard old) {
    super.didUpdateWidget(old);
    if (widget.focusNode != old.focusNode) {
      _isFocused = widget.focusNode?.hasFocus ?? false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onFocusChange: (focused) {
        if (mounted) setState(() => _isFocused = focused);
        if (focused && widget.onFocus != null) {
          widget.onFocus!();
        }
      },
      onKeyEvent: (node, event) {
        if (widget.onRight == null && event.logicalKey == LogicalKeyboardKey.arrowRight) {
          return KeyEventResult.handled;
        }
        if (widget.onLeft == null && event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          return KeyEventResult.handled;
        }
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            widget.onLeft!();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            widget.onRight!();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.select) {
            widget.onSelected?.call();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowUp && widget.onUp != null) {
            widget.onUp!();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowDown && widget.onDown != null) {
            widget.onDown!();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: BrowserCard(
        item: widget.item,
        isFocused: _isFocused,
      ),
    );
  }
}
