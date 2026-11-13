import 'package:flutter/foundation.dart';

/// Agent 动过画布（生成新图、改写提示词）时浮起的一条提示。
///
/// 桌面版这条提示由「外部 Agent 桥」推事件；手机端 Agent 是内建宿主，没有外部桥，
/// 所以从控制器已有的「正在执行工具」快照里推导：某个画布工具从执行中消失、且留下
/// 了结束事件，就等于画布被改过了。
@immutable
class AgentCanvasNoticeEvent {
  const AgentCanvasNoticeEvent({required this.id, required this.at});

  /// 工具调用 id，用来判断是不是同一条提示（重复不重播）。
  final String id;
  final DateTime at;
}
