import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../kit/ui_colors.dart';

/// 「Anlas」像素小人：桌面 2.3.2/2.3.3 的 Agent 标志。
///
/// 桌面版是带动画的小人（待机眨眼、思考冒点、生成时放宝石…）。手机端只保留
/// **静态一帧**：按状态取 [AgentToggleBadge] 的代表姿势，仍然能一眼看出在干嘛；
/// 动画帧和粒子效果没有移植，省电也省代码。

/// Sprite 行的名字 → 像素行；给形状/表情回归测试用。
@visibleForTesting
Map<String, List<String>> get agentMarkFrames => {
  'base': _F.base.rows,
  'squash': _F.squash.rows,
  'stretch': _F.stretch.rows,
  'breathe': _F.breathe.rows,
  'melt': _F.melt.rows,
  'melt2': _F.melt2.rows,
  'blink': _F.blink.rows,
  'happy': _F.happy.rows,
  'lookL': _F.lookL.rows,
  'lookR': _F.lookR.rows,
  'lookU': _F.lookU.rows,
  'ouch': _F.ouch.rows,
  'talkA': _F.talkA.rows,
  'talkB': _F.talkB.rows,
  'squashBlink': _F.squashBlink.rows,
  'breatheBlink': _F.breatheBlink.rows,
  'breatheL': _F.breatheL.rows,
  'breatheR': _F.breatheR.rows,
  'breatheU': _F.breatheU.rows,
  'breatheOuch': _F.breatheOuch.rows,
};

/// Agent 此刻在做什么。多个聊天同时活动时，入口角标取优先级最高的一个：
/// [question]、[approval]、[runLimit]、[error]、[generating]、[compacting]、
/// [tool]、[writing]、[thinking]、[starting]、[done]，最后是 [none]。
enum AgentToggleBadge {
  /// 空闲：没在跑，也没有没看过的结果。
  none,

  /// 聊天正在启动宿主，或排队等请求名额。
  starting,

  /// 在跑，推理流式输出中，或还在等第一段输出。
  thinking,

  /// 正在流出可见的回复文字。
  writing,

  /// 正在执行工具（不是生成图片）。
  tool,

  /// 正在跑生成图片类工具（花 Anlas）。
  generating,

  /// 正在压缩会话上下文。
  compacting,

  /// 跑完了、结果正常，但用户还没看。
  done,

  /// 跑完但出错/被中断，用户还没看。
  error,

  /// 撞到单次请求上限，等用户决定。
  runLimit,

  /// Agent 向用户提问了。
  question,

  /// 有生成/图片使用待确认。
  approval;

  bool get isRunning => switch (this) {
    starting || thinking || writing || tool || generating || compacting => true,
    _ => false,
  };

  bool get isWaiting =>
      this == question || this == approval || this == runLimit;
}

/// 角标圆点颜色；[AgentToggleBadge.none] 不画。
Color? agentBadgeColor(UiColors c, AgentToggleBadge badge) => switch (badge) {
  AgentToggleBadge.none => null,
  AgentToggleBadge.done => c.ok,
  AgentToggleBadge.error => c.error,
  AgentToggleBadge.runLimit || AgentToggleBadge.question => c.warn,
  AgentToggleBadge.approval => c.warn,
  _ => c.accent,
};

/// 静态小人。`color` 传了就是单色剪影（深底、菜单里的小图标）；`tileSize`
/// 传了就在背后画一块实心方砖（工具栏展开态）。
class AgentMark extends StatelessWidget {
  const AgentMark({
    super.key,
    this.size = 18,
    this.badge = AgentToggleBadge.none,
    this.color,
    this.tileSize,
  });

  final double size;
  final AgentToggleBadge badge;
  final Color? color;
  final double? tileSize;

  @override
  Widget build(BuildContext context) {
    final step = _Seq.still(badge);
    return _AgentArt(
      size: tileSize ?? size,
      spriteSize: size,
      pose: step.pose,
      cells: step.symbols,
      onTile: tileSize != null,
      tile: tileSize != null,
      color: color,
    );
  }
}

/// 侧栏/面板标题左侧的状态标志：实心方砖 + 状态圆点。
class AgentStatusMark extends StatelessWidget {
  const AgentStatusMark({
    super.key,
    this.size = 26,
    this.badge = AgentToggleBadge.none,
  });

  final double size;
  final AgentToggleBadge badge;

  @override
  Widget build(BuildContext context) {
    final dot = agentBadgeColor(context.ui, badge);
    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          AgentMark(size: size * .69, badge: badge, tileSize: size),
          if (dot != null) _BadgeDot(badge: badge, color: dot, inset: -2),
        ],
      ),
    );
  }
}

/// 工具栏里的 Agent 开关（生图页提示词工具区、窗口标题栏）。
class AgentToggleButton extends StatefulWidget {
  const AgentToggleButton({
    super.key,
    required this.expanded,
    required this.onPressed,
    required this.tooltip,
    this.size = 28,
    this.badge = AgentToggleBadge.none,
  });
  final bool expanded;
  final VoidCallback onPressed;
  final String tooltip;
  final double size;

  /// 只在收起（[expanded] 为 false）时画。
  final AgentToggleBadge badge;

  @override
  State<AgentToggleButton> createState() => _AgentToggleButtonState();
}

class _AgentToggleButtonState extends State<AgentToggleButton> {
  var _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.ui;
    final on = widget.expanded;
    final dot = on ? null : agentBadgeColor(c, widget.badge);
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: Container(
            key: const Key('agent-toggle'),
            width: widget.size,
            height: widget.size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on
                  ? null
                  : _hover
                  ? c.hover
                  : null,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                AgentMark(
                  size: widget.size * .64,
                  badge: widget.badge,
                  tileSize: on ? widget.size : null,
                ),
                if (dot != null) _BadgeDot(badge: widget.badge, color: dot),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BadgeDot extends StatelessWidget {
  const _BadgeDot({required this.badge, required this.color, this.inset});

  final AgentToggleBadge badge;
  final Color color;
  final double? inset;

  @override
  Widget build(BuildContext context) => Positioned(
    right: inset ?? -5,
    top: inset ?? -5,
    child: Container(
      key: Key('agent-toggle-badge-${badge.name}'),
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: Border.all(color: context.ui.bg, width: 1.5),
      ),
    ),
  );
}

/// 一帧画面：方块地砖 + 9×9 像素小人 + 状态符号。
class _AgentArt extends StatelessWidget {
  const _AgentArt({
    required this.size,
    required this.spriteSize,
    required this.pose,
    required this.cells,
    this.onTile = false,
    this.tile = false,
    this.color,
  });

  final double size;
  final double spriteSize;
  final _Pose pose;
  final List<_Cell> cells;
  final bool onTile;
  final bool tile;
  final Color? color;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _AgentPainter(
      art: this,
      colors: context.ui,
      dpr: MediaQuery.devicePixelRatioOf(context),
      screenOrigin: () =>
          (context.findRenderObject()! as RenderBox).localToGlobal(Offset.zero),
    ),
  );
}

class _AgentPainter extends CustomPainter {
  const _AgentPainter({
    required this.art,
    required this.colors,
    required this.dpr,
    required this.screenOrigin,
  });

  final _AgentArt art;
  final UiColors colors;
  final double dpr;
  final Offset Function() screenOrigin;

  double _pixels(double value) => (value * dpr).round() / dpr;

  @override
  void paint(Canvas canvas, Size size) {
    final pose = art.pose;
    final origin = screenOrigin();
    Offset snap(Offset point) => Offset(
      _pixels(origin.dx + point.dx) - origin.dx,
      _pixels(origin.dy + point.dy) - origin.dy,
    );

    final center = size.center(Offset.zero);
    final paint = Paint()..isAntiAlias = false;
    final palette = colors.agentPixels(onTile: art.onTile);
    if (art.tile) {
      final edge = art.size;
      final start = snap(center - Offset(edge / 2, edge / 2));
      _paintTile(canvas, paint, start & Size.square(_pixels(edge)));
    }

    final cell = _pixels(art.spriteSize / 9);
    final base = snap(center - Offset(cell * 4.5, cell * 4.5));
    final body = base + Offset(pose.dx * cell, pose.dy * cell);
    void pixel(Offset at, int x, int y, Color color) => canvas.drawRect(
      Rect.fromLTWH(at.dx + x * cell, at.dy + y * cell, cell, cell),
      paint..color = color,
    );

    final rows = pose.rows;
    bool filled(int x, int y) {
      if (y < 0 || y >= 9) return false;
      final row = rows[y];
      final i = x + (row.length - 9) ~/ 2;
      return i >= 0 && i < row.length && row[i] != '.';
    }

    // 展开态在实心砖上，用一圈品牌蓝描边，免得浅色身体糊在砖上。
    if (art.onTile) {
      for (var y = -1; y <= 9; y++) {
        for (var x = -2; x <= 10; x++) {
          if (filled(x, y)) continue;
          if (filled(x - 1, y) ||
              filled(x + 1, y) ||
              filled(x, y - 1) ||
              filled(x, y + 1)) {
            pixel(body, x, y, colors.agentTile);
          }
        }
      }
    }
    final tint = art.color;
    for (var y = 0; y < 9; y++) {
      final row = rows[y];
      for (var i = 0; i < row.length; i++) {
        final x = i - (row.length - 9) ~/ 2;
        final color =
            tint ??
            switch (row[i]) {
              '#' => palette.body,
              '+' => palette.highlight,
              '=' => palette.shadow,
              'o' => palette.eyes,
              'w' => colors.onBrand,
              _ => null,
            };
        if (color != null) pixel(body, x, y, color);
      }
    }

    for (final (x, y, ink, opacity) in art.cells) {
      final color =
          tint ??
          switch (ink) {
            _Ink.accent => colors.accent,
            _Ink.warn => colors.warn,
            _Ink.faint => colors.faint,
            _Ink.star => colors.star,
            _Ink.water => colors.agentPixels(onTile: false).highlight,
          };
      pixel(base, x, y, color.withValues(alpha: opacity));
    }
  }

  void _paintTile(Canvas canvas, Paint paint, Rect r) {
    final cut = _pixels(2);
    final path = Path()
      ..addPolygon([
        Offset(r.left + cut, r.top),
        Offset(r.right - cut, r.top),
        Offset(r.right - cut, r.top + cut),
        Offset(r.right, r.top + cut),
        Offset(r.right, r.bottom - cut),
        Offset(r.right - cut, r.bottom - cut),
        Offset(r.right - cut, r.bottom),
        Offset(r.left + cut, r.bottom),
        Offset(r.left + cut, r.bottom - cut),
        Offset(r.left, r.bottom - cut),
        Offset(r.left, r.top + cut),
        Offset(r.left + cut, r.top + cut),
      ], true);
    canvas.save();
    canvas.clipPath(path, doAntiAlias: false);
    canvas.drawRect(r, paint..color = colors.agentTile);
    final highlight = paint..color = colors.onBrand.withValues(alpha: .3);
    canvas.drawRect(Rect.fromLTWH(r.left, r.top, r.width, cut), highlight);
    canvas.drawRect(
      Rect.fromLTWH(r.left, r.top + cut, cut, r.height - cut * 2),
      highlight,
    );
    final shadow = paint..color = colors.agentTileBevel;
    canvas.drawRect(
      Rect.fromLTWH(r.left, r.bottom - cut, r.width, cut),
      shadow,
    );
    canvas.drawRect(
      Rect.fromLTWH(r.right - cut, r.top + cut, cut, r.height - cut * 2),
      shadow,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_AgentPainter old) =>
      dpr != old.dpr ||
      colors.dark != old.colors.dark ||
      colors.accent != old.colors.accent ||
      colors.bg != old.colors.bg ||
      art.spriteSize != old.art.spriteSize ||
      art.size != old.art.size ||
      art.color != old.art.color ||
      art.onTile != old.art.onTile ||
      art.tile != old.art.tile ||
      !identical(art.pose.rows, old.art.pose.rows) ||
      art.pose.dx != old.art.pose.dx ||
      art.pose.dy != old.art.pose.dy ||
      !listEquals(art.cells, old.art.cells);
}

/// A frame centered on the 9x9 grid, moved by cells (negative [dy] is up).
typedef _Pose = ({List<String> rows, int dx, int dy});

/// A loose pixel drawn relative to the unmoved sprite origin, in cells.
typedef _Cell = (int x, int y, _Ink ink, double opacity);

enum _Ink { accent, warn, faint, star, water }

/// Sprite frames. `#` body, `+` highlight, `=` shadow, `o` eyes, `w` eye
/// shine. Rows are 9 or 11 cells wide, with wide rows extending one cell past
/// each side of the grid.
abstract final class _F {
  static const _base = [
    '....#....',
    '...+#=...',
    '..+###=..',
    '.+#####=.',
    '#+######=',
    '##wo#wo#=',
    '##oo#oo#=',
    '=#######=',
    '.=======.',
  ];
  static const _squash = [
    '...........',
    '...........',
    '....+#=....',
    '...+###=...',
    '..+#####=..',
    '.+#######=.',
    '+##wo#wo##=',
    '###oo#oo##=',
    '.=========.',
  ];
  static const _stretch = [
    '....#....',
    '....#....',
    '...+#=...',
    '..+###=..',
    '..+###=..',
    '..wo#wo..',
    '..oo#oo..',
    '..=###=..',
    '...===...',
  ];
  static const _breathe = [
    '...........',
    '.....#.....',
    '....+#=....',
    '...+###=...',
    '..+#####=..',
    '.+#wo#wo#=.',
    '###oo#oo##=',
    '=#########=',
    '.=========.',
  ];
  static const _melt = [
    '...........',
    '...........',
    '...........',
    '...........',
    '...........',
    '..+#####=..',
    '.+#oo#oo#=.',
    '+#########=',
    '===========',
  ];
  static const _melt2 = [
    '...........',
    '...........',
    '...........',
    '...........',
    '...+###=...',
    '..+#####=..',
    '.+#oo#oo#=.',
    '+#########=',
    '===========',
  ];

  static const _blink = {5: '#+######=', 6: '##oo#oo#='};
  static const _happy = {5: '##o###o#=', 6: '#o#o#o#o='};
  static const _lookL = {5: '#wo#wo##=', 6: '#oo#oo##='};
  static const _lookR = {5: '###wo#wo=', 6: '###oo#oo='};
  static const _lookU = {4: '#+wo#wo#=', 5: '##oo#oo#=', 6: '########='};
  static const _ouch = {4: '#+o###o#=', 5: '###o#o##=', 6: '##o###o#='};

  static _Pose _p(List<String> rows) => (rows: rows, dx: 0, dy: 0);
  static _Pose _face(
    Map<int, String> eyes, [
    List<String> body = _base,
    int rowOffset = 0,
  ]) {
    const eyePixels = {'o', 'w'};
    final rows = [...body];
    for (final entry in eyes.entries) {
      final y = entry.key + rowOffset;
      final pixels = body[y].split('');
      final inset = (pixels.length - 9) ~/ 2;
      for (var x = 0; x < 9; x++) {
        if (pixels[x + inset] != '.' &&
            (eyePixels.contains(entry.value[x]) ||
                eyePixels.contains(_base[entry.key][x]))) {
          pixels[x + inset] = entry.value[x];
        }
      }
      rows[y] = pixels.join();
    }
    return _p(rows);
  }

  static final base = _p(_base);
  static final squash = _p(_squash);
  static final stretch = _p(_stretch);
  static final breathe = _p(_breathe);
  static final melt = _p(_melt);
  static final melt2 = _p(_melt2);
  // The original blink adds a shoulder highlight as well as closing its eyes.
  static final blink = _p(_face(_blink).rows..[5] = _blink[5]!);
  static final happy = _face(_happy);
  static final lookL = _face(_lookL);
  static final lookR = _face(_lookR);
  static final lookU = _face(_lookU);
  static final ouch = _face(_ouch);
  static final talkA = _face({7: '=###o###='});
  static final talkB = _face({7: '=##ooo##='});
  static final squashBlink = _face(_blink, _squash, 1);
  static final breatheBlink = _face(_blink, _breathe);
  static final breatheL = _face(_lookL, _breathe);
  static final breatheR = _face(_lookR, _breathe);
  static final breatheU = _face(_lookU, _breathe);
  static final breatheOuch = _face(_ouch, _breathe);
}

/// Status symbols live in the empty space above and right of the head.
abstract final class _Glyph {
  static const dots = [(2, -2), (4, -2), (6, -2)];

  static List<_Cell> of(
    List<(int, int)> cells,
    _Ink ink, {
    int dx = 0,
    int dy = 0,
    double opacity = 1,
  }) => [for (final (x, y) in cells) (x + dx, y + dy, ink, opacity)];
}

class _Step {
  const _Step(this.pose, this.symbols);

  final _Pose pose;
  final List<_Cell> symbols;
}

abstract final class _Seq {
  static List<_Cell> _dots(int count, [double opacity = 1]) => _Glyph.of(
    _Glyph.dots.take(count).toList(),
    _Ink.accent,
    opacity: opacity,
  );

  /// One representative frame per state; the desktop version animates these.
  static _Step still(AgentToggleBadge badge) => switch (badge) {
    AgentToggleBadge.none => _Step(_F.base, const []),
    AgentToggleBadge.starting => _Step(_F.lookR, const []),
    AgentToggleBadge.thinking => _Step(_F.lookU, _dots(3)),
    AgentToggleBadge.writing => _Step(_F.talkB, const []),
    AgentToggleBadge.tool => _Step(_F.lookR, const []),
    AgentToggleBadge.generating => _Step(_F.happy, const []),
    AgentToggleBadge.compacting => _Step(_F.squashBlink, const []),
    AgentToggleBadge.done => _Step(_F.happy, const []),
    AgentToggleBadge.error => _Step(_F.ouch, const []),
    AgentToggleBadge.runLimit => _Step(_F.melt, const []),
    AgentToggleBadge.question => _Step(_F.lookU, const []),
    AgentToggleBadge.approval => _Step(_F.happy, const []),
  };
}
