import 'dart:io';

import 'package:nai_launcher/presentation/widgets/common/studio_material.dart';
import 'package:nai_launcher/presentation/widgets/common/studio_icons.dart';

import '../../../core/utils/localization_extension.dart';
import '../../mobile/mobile_context_menu.dart';
import '../common/image_action_menu.dart';

enum LocalImageContextAction {
  details,
  sendToTextToImage,
  sendToImg2Img,
  sendToStyleTransfer,
  sendToPreciseReference,
  saveToPreciseRefLibrary,
  sendToKrita,
  upscale,
  importMetadata,
  placeOnCanvas,
  copyImage,
  copyPrompt,
  copySeed,
  moveTo,
  copyTo,
  showInFolder,

  /// 手机端：保存到系统相册（Android MediaStore）。
  ///
  /// 桌面右键菜单不展示该动作，避免改变桌面入口。
  saveToAlbum,

  /// 手机端：把图片交给系统分享面板（Android ACTION_SEND）。
  ///
  /// 桌面右键菜单不展示该动作，避免改变桌面入口。
  share,

  /// 手机端：心形收藏开关（桌面是卡片悬停按钮，触屏无 hover）。
  toggleFavorite,
  delete,
}

class LocalImageContextMenu {
  const LocalImageContextMenu._();

  static Future<LocalImageContextAction?> show(
    BuildContext context, {
    required Offset position,
    required bool hasImportableMetadata,
    required bool hasPrompt,
    required bool hasSeed,
    required bool isKritaConnected,
    bool canPlaceOnCanvas = true,
  }) {
    final l = context.l10n;
    ImageMenuAction<LocalImageContextAction> item(
      LocalImageContextAction value,
      String label,
      IconData icon, {
      bool enabled = true,
      bool destructive = false,
    }) => ImageMenuAction(
      value: value,
      label: label,
      icon: icon,
      enabled: enabled,
      destructive: destructive,
    );
    return ImageActionMenu.show<LocalImageContextAction>(
      context,
      position: position,
      quickActions: [
        item(
          LocalImageContextAction.copyImage,
          l.imageViewer_copyImage,
          StudioIcons.galleryCopy,
        ),
        item(
          LocalImageContextAction.copyPrompt,
          l.localGallery_copyPrompt,
          StudioIcons.galleryCopy,
          enabled: hasPrompt,
        ),
      ],
      actions: [
        item(
          LocalImageContextAction.details,
          l.imageMenu_details,
          Icons.info_outline,
        ),
        item(
          LocalImageContextAction.sendToImg2Img,
          l.drop_img2img,
          StudioIcons.imageToImage,
        ),
        if (hasImportableMetadata)
          item(
            LocalImageContextAction.importMetadata,
            l.localGallery_importImageMetadata,
            StudioIcons.galleryImport,
          ),
        item(
          LocalImageContextAction.placeOnCanvas,
          l.img2img_placeOnCanvas,
          Icons.crop_free,
          enabled: canPlaceOnCanvas,
        ),
        item(
          LocalImageContextAction.showInFolder,
          l.localGallery_showInFolder,
          StudioIcons.galleryReveal,
        ),
        const ImageMenuAction.divider(),
        ImageMenuAction(
          label: l.imageMenu_creation,
          icon: StudioIcons.referenceFocus,
          children: [
            item(
              LocalImageContextAction.sendToTextToImage,
              l.onlineGallery_sendToTextToImage,
              StudioIcons.gallerySpark,
              enabled: hasImportableMetadata,
            ),
            item(
              LocalImageContextAction.sendToStyleTransfer,
              l.drop_vibeTransfer,
              StudioIcons.styleTransfer,
            ),
            item(
              LocalImageContextAction.sendToPreciseReference,
              l.drop_characterReference,
              StudioIcons.referenceFocus,
            ),
            item(
              LocalImageContextAction.saveToPreciseRefLibrary,
              l.drop_saveToPreciseRefLibrary,
              StudioIcons.galleryBookmarkAdd,
            ),
            if (!Platform.isAndroid)
              // Local / advanced upscale depends on bundled desktop
              // executables and has no Android implementation.
              item(
                LocalImageContextAction.upscale,
                l.gallery_upscale,
                StudioIcons.galleryUpscale,
              ),
            item(
              LocalImageContextAction.sendToKrita,
              l.localGallery_sendToKrita,
              StudioIcons.galleryBrush,
              enabled: isKritaConnected,
            ),
          ],
        ),
        ImageMenuAction(
          label: l.imageMenu_fileActions,
          icon: Icons.folder_outlined,
          children: [
            item(
              LocalImageContextAction.moveTo,
              l.localGallery_moveTo,
              StudioIcons.galleryMove,
            ),
            item(
              LocalImageContextAction.copyTo,
              l.localGallery_copyTo,
              StudioIcons.galleryCopy,
            ),
          ],
        ),
        const ImageMenuAction.divider(),
        item(
          LocalImageContextAction.delete,
          l.common_delete,
          StudioIcons.galleryTrash,
          destructive: true,
        ),
      ],
    );
  }

  /// 手机端长按菜单：把与桌面右键相同的动作拍平成 bottom sheet。
  ///
  /// 桌面右键菜单 [show] 保持原样；这里只组装 [MobileMenuItem]，动作仍交回
  /// 宿主按 [LocalImageContextAction] 统一分派，避免两套行为漂移。
  static Future<LocalImageContextAction?> showMobile(
    BuildContext context, {
    String? title,
    required bool hasImportableMetadata,
    required bool hasPrompt,
    required bool hasSeed,
    required bool isKritaConnected,
    required bool isFavorite,
    bool canPlaceOnCanvas = true,
  }) async {
    final l = context.l10n;
    LocalImageContextAction? selected;
    MobileMenuItem item(
      LocalImageContextAction value,
      String label,
      IconData icon, {
      bool enabled = true,
      bool destructive = false,
    }) => MobileMenuItem(
      label: label,
      icon: icon,
      enabled: enabled,
      destructive: destructive,
      onTap: () => selected = value,
    );

    await showMobileContextMenu(
      context,
      title: title,
      items: [
        item(
          LocalImageContextAction.details,
          l.imageMenu_details,
          Icons.info_outline,
        ),
        item(
          LocalImageContextAction.toggleFavorite,
          isFavorite ? l.online_unfavorite : l.online_favorited,
          isFavorite
              ? StudioIcons.galleryHeartFilled
              : StudioIcons.galleryHeart,
        ),
        item(
          LocalImageContextAction.copyImage,
          l.imageViewer_copyImage,
          StudioIcons.galleryCopy,
        ),
        item(
          LocalImageContextAction.copyPrompt,
          l.localGallery_copyPrompt,
          StudioIcons.galleryCopy,
          enabled: hasPrompt,
        ),
        item(
          LocalImageContextAction.copySeed,
          l.imageViewer_copySeed,
          Icons.tag,
          enabled: hasSeed,
        ),
        if (hasImportableMetadata)
          item(
            LocalImageContextAction.importMetadata,
            l.localGallery_importImageMetadata,
            StudioIcons.galleryImport,
          ),
        item(
          LocalImageContextAction.sendToImg2Img,
          l.drop_img2img,
          StudioIcons.imageToImage,
        ),
        item(
          LocalImageContextAction.sendToStyleTransfer,
          l.drop_vibeTransfer,
          StudioIcons.styleTransfer,
        ),
        item(
          LocalImageContextAction.sendToPreciseReference,
          l.drop_characterReference,
          StudioIcons.referenceFocus,
        ),
        item(
          LocalImageContextAction.saveToPreciseRefLibrary,
          l.drop_saveToPreciseRefLibrary,
          StudioIcons.galleryBookmarkAdd,
        ),
        item(
          LocalImageContextAction.placeOnCanvas,
          l.img2img_placeOnCanvas,
          Icons.crop_free,
          enabled: canPlaceOnCanvas,
        ),
        if (isKritaConnected)
          item(
            LocalImageContextAction.sendToKrita,
            l.localGallery_sendToKrita,
            StudioIcons.galleryBrush,
          ),
        item(
          LocalImageContextAction.moveTo,
          l.localGallery_moveTo,
          StudioIcons.galleryMove,
        ),
        item(
          LocalImageContextAction.copyTo,
          l.localGallery_copyTo,
          StudioIcons.galleryCopy,
        ),
        item(
          LocalImageContextAction.showInFolder,
          l.localGallery_showInFolder,
          StudioIcons.galleryReveal,
        ),
        if (Platform.isAndroid) ...[
          item(
            LocalImageContextAction.share,
            l.common_share,
            StudioIcons.gallerySend,
          ),
          item(
            LocalImageContextAction.saveToAlbum,
            l.localGallery_saveToAlbum,
            Icons.save_alt_rounded,
          ),
        ],
        item(
          LocalImageContextAction.delete,
          l.common_delete,
          StudioIcons.galleryTrash,
          destructive: true,
        ),
      ],
    );
    return selected;
  }
}
