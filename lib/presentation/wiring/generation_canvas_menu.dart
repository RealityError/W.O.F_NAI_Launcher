import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/localization_extension.dart';
import '../mobile/mobile_context_menu.dart';
import '../providers/image_generation_provider.dart';
import '../screens/generation/widgets/canvas/generated_image_actions.dart';
import '../ui/gen/gen_canvas.dart';
import '../ui/gen/gen_contract.dart';
import '../ui/gen/gen_page.dart';
import '../ui/kit/ui_image_menu.dart';
import '../widgets/common/image_action_menu.dart';
import '../widgets/common/studio_icons.dart';
import '../utils/krita_send_helper.dart';
import '../utils/precise_ref_library_import_helper.dart';
import 'generation_operations.dart';
import 'generation_history_actions.dart';

class GenerationCanvasMenuWiring extends ConsumerStatefulWidget {
  const GenerationCanvasMenuWiring({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<GenerationCanvasMenuWiring> createState() =>
      _GenerationCanvasMenuWiringState();
}

class _GenerationCanvasMenuWiringState
    extends ConsumerState<GenerationCanvasMenuWiring> {
  late final _onOpen = _open;

  void _open(BuildContext context, String id, Offset position) {
    final image = ref
        .read(generationHistoryActionsProvider)
        .images
        .where((image) => image.id == id)
        .firstOrNull;
    if (image != null) {
      unawaited(openGenerationCanvasMenu(context, ref, image, position));
    }
  }

  void _openMobile(BuildContext context, String id) {
    final image = ref
        .read(generationHistoryActionsProvider)
        .images
        .where((image) => image.id == id)
        .firstOrNull;
    if (image != null) {
      unawaited(openGenerationCanvasMenuMobile(context, ref, image));
    }
  }

  @override
  Widget build(BuildContext context) => GenCanvasMenuScope(
    onOpen: _onOpen,
    onOpenMobile: _openMobile,
    child: widget.child,
  );
}

/// 手机端：把右键菜单拍平成底部菜单，动作与桌面右键同源。
///
/// `打开文件夹` 是桌面文件管理动作，手机不给；其余条目与桌面右键一致。
Future<void> openGenerationCanvasMenuMobile(
  BuildContext context,
  WidgetRef ref,
  GeneratedImage image,
) async {
  final scope = GenScope.read(context);
  final a = scope.actions;
  final l = context.l10n;
  final id = image.id;
  final canInput = image.canUseAsGenerationInput && !scope.data.canvas.locked;
  scope.controller.closePopover();
  await showMobileContextMenu(
    context,
    items: [
      MobileMenuItem(
        label: l.shortcut_action_save_image,
        icon: Icons.save_alt,
        enabled: image.canSave,
        onTap: () => a.onSaveImage(id),
      ),
      MobileMenuItem(
        label: l.shortcut_action_copy_image,
        icon: Icons.copy,
        enabled: image.canSave,
        onTap: () => a.onCopyImage(id),
      ),
      MobileMenuItem(
        label: l.imageMenu_details,
        icon: Icons.open_in_full,
        onTap: () => a.onOpenViewer(id),
      ),
      MobileMenuItem(
        label: l.common_delete,
        icon: Icons.delete_outline,
        destructive: true,
        onTap: () => a.onDeleteImages([id]),
      ),
      MobileMenuItem(
        label: l.drop_img2img,
        icon: Icons.image_outlined,
        enabled: canInput,
        onTap: () => a.onSendTo(id, GenSendTarget.img2img),
      ),
      MobileMenuItem(
        label: l.drop_vibeTransfer,
        icon: StudioIcons.vibeLibrary,
        enabled: canInput && scope.data.refs.vibes != null,
        onTap: () => a.onSendTo(id, GenSendTarget.vibe),
      ),
      MobileMenuItem(
        label: l.drop_characterReference,
        icon: StudioIcons.preciseReference,
        enabled: canInput && scope.data.refs.precise != null,
        onTap: () => a.onSendTo(id, GenSendTarget.precise),
      ),
      MobileMenuItem(
        label: l.drop_saveToPreciseRefLibrary,
        icon: Icons.bookmark_add_outlined,
        enabled: canInput,
        onTap: () =>
            unawaited(saveBytesToPreciseRefLibrary(ref, context, image.bytes)),
      ),
    ],
  );
}

/// 复用旧图片菜单：顶部快捷操作，编辑与更多操作分别折入子菜单。
Future<void> openGenerationCanvasMenu(
  BuildContext context,
  WidgetRef ref,
  GeneratedImage image,
  Offset position,
) async {
  final scope = GenScope.read(context);
  final a = scope.actions;
  final l = context.l10n;
  final id = image.id;
  final canInput = image.canUseAsGenerationInput && !scope.data.canvas.locked;
  final operations = GenerationOperations(ref, context, () => context.mounted);
  void run(Future<void> Function() task) => operations.run(task);
  ImageMenuAction<VoidCallback> action(
    String key,
    String label,
    IconData icon,
    VoidCallback callback, {
    bool enabled = true,
    bool destructive = false,
  }) => ImageMenuAction(
    key: Key('gen-canvas-menu-$key'),
    label: label,
    icon: icon,
    value: callback,
    enabled: enabled,
    destructive: destructive,
  );
  scope.controller.closePopover();
  final selected = await UiImageMenu.show<VoidCallback>(
    context,
    position: position,
    quickActions: [
      action(
        'save',
        l.shortcut_action_save_image,
        Icons.save_alt,
        () => a.onSaveImage(id),
        enabled: image.canSave,
      ),
      action(
        'copy',
        l.shortcut_action_copy_image,
        Icons.copy,
        () => a.onCopyImage(id),
        enabled: image.canSave,
      ),
    ],
    actions: [
      action(
        'viewer',
        l.imageMenu_details,
        Icons.open_in_full,
        () => a.onOpenViewer(id),
      ),
      action(
        'delete',
        l.common_delete,
        Icons.delete_outline,
        () => a.onDeleteImages([id]),
        destructive: true,
      ),
      action(
        'img2img',
        l.drop_img2img,
        Icons.image_outlined,
        () => a.onSendTo(id, GenSendTarget.img2img),
        enabled: canInput,
      ),
      action(
        'vibe',
        l.drop_vibeTransfer,
        StudioIcons.vibeLibrary,
        () => a.onSendTo(id, GenSendTarget.vibe),
        enabled: canInput && scope.data.refs.vibes != null,
      ),
      action(
        'precise',
        l.drop_characterReference,
        StudioIcons.preciseReference,
        () => a.onSendTo(id, GenSendTarget.precise),
        enabled: canInput && scope.data.refs.precise != null,
      ),
      const ImageMenuAction.divider(),
      ImageMenuAction(
        key: const Key('gen-canvas-menu-edit-group'),
        label: l.imageMenu_editAndDerive,
        icon: Icons.auto_fix_high_outlined,
        children: [
          action(
            'edit',
            l.img2img_editImage,
            Icons.edit_outlined,
            () => a.onEditImage(id),
            enabled: canInput,
          ),
          action(
            'inpaint',
            l.img2img_inpaint,
            Icons.draw_outlined,
            () => a.onInpaint(id),
            enabled: canInput,
          ),
          action(
            'variations',
            l.img2img_generateVariations,
            Icons.auto_awesome_motion_outlined,
            () => a.onVariations(id),
            enabled: canInput,
          ),
          action(
            'tools',
            l.img2img_directorTools,
            Icons.auto_fix_high_outlined,
            () => a.onSendToTools(id),
            enabled: canInput,
          ),
          action(
            'enhance',
            l.img2img_enhance,
            Icons.auto_awesome_outlined,
            () => a.onEnhance(id),
            enabled: canInput,
          ),
          action(
            'upscale',
            l.image_upscale,
            Icons.zoom_out_map_rounded,
            () => a.onUpscale(id),
            enabled: canInput,
          ),
        ],
      ),
      ImageMenuAction(
        key: const Key('gen-canvas-menu-more-group'),
        label: l.imageMenu_more,
        icon: Icons.more_horiz,
        children: [
          action(
            'precise-library',
            l.drop_saveToPreciseRefLibrary,
            Icons.bookmark_add_outlined,
            () => run(
              () => saveBytesToPreciseRefLibrary(ref, context, image.bytes),
            ),
            enabled: canInput,
          ),
          action(
            'reveal',
            l.shortcut_action_open_folder,
            Icons.folder_open,
            () => a.onReveal(id),
            enabled: image.canSave,
          ),
          action(
            'krita',
            l.gallery_sendToKritaAction,
            Icons.brush_outlined,
            () => KritaSendHelper.sendImageBytes(
              context,
              ref,
              image.bytes,
              name: GeneratedImageActions(ref).previewImageFileName(image),
            ),
            enabled: canInput,
          ),
        ],
      ),
    ],
  );
  if (context.mounted) selected?.call();
}
