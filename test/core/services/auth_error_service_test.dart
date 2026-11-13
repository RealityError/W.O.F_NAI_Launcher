import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/services/auth_error_service.dart';
import 'package:nai_launcher/l10n/app_localizations_zh.dart';
import 'package:nai_launcher/presentation/providers/auth_provider.dart';

void main() {
  group('AuthState.parseError', () {
    test('HTTP 404 maps to endpointNotFound', () {
      final request = RequestOptions(path: '/user/subscription');
      final error = DioException(
        requestOptions: request,
        response: Response(requestOptions: request, statusCode: 404),
        type: DioExceptionType.badResponse,
      );

      expect(AuthState.parseError(error), (
        AuthErrorCode.endpointNotFound,
        404,
      ));
    });

    test('HTTP 401 still maps to authFailed', () {
      final request = RequestOptions(path: '/user/subscription');
      final error = DioException(
        requestOptions: request,
        response: Response(requestOptions: request, statusCode: 401),
        type: DioExceptionType.badResponse,
      );

      expect(AuthState.parseError(error), (AuthErrorCode.authFailed, 401));
    });

    test('HTTP 500 still maps to serverError', () {
      final request = RequestOptions(path: '/user/subscription');
      final error = DioException(
        requestOptions: request,
        response: Response(requestOptions: request, statusCode: 503),
        type: DioExceptionType.badResponse,
      );

      expect(AuthState.parseError(error), (AuthErrorCode.serverError, 503));
    });
  });

  group('AuthErrorService.endpointNotFound', () {
    final service = AuthErrorService();
    final l10n = AppLocalizationsZh();

    test('returns endpoint unavailable text without placeholder noise', () {
      final text = service.getErrorText(
        l10n,
        AuthErrorCode.endpointNotFound,
        404,
      );

      expect(text, l10n.auth_error_endpointUnavailable);
      expect(text.contains('{'), isFalse);
    });

    test('provides recovery hint about API address', () {
      expect(
        service.getErrorRecoveryHint(l10n, AuthErrorCode.endpointNotFound, 404),
        l10n.auth_error_endpointUnavailable_hint,
      );
    });

    test('getErrorMessage bundles text and hint', () {
      final message = service.getErrorMessage(
        l10n,
        AuthErrorCode.endpointNotFound,
        404,
      );

      expect(message.errorText, l10n.auth_error_endpointUnavailable);
      expect(message.recoveryHint, l10n.auth_error_endpointUnavailable_hint);
      expect(message.hasRecoveryHint, isTrue);
    });
  });
}
