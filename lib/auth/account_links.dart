import 'package:url_launcher/url_launcher.dart';

/// Public legal routes shared with the Typeflux website and macOS client.
Uri accountLegalUri({
  required bool privacy,
  required bool chinese,
}) => Uri.parse(
  'https://typeflux.app${chinese ? '/zh-CN' : ''}/${privacy ? 'privacy' : 'terms'}',
);

Future<bool> openAccountLegal({required bool privacy, required bool chinese}) =>
    launchUrl(
      accountLegalUri(privacy: privacy, chinese: chinese),
      mode: LaunchMode.externalApplication,
    );
