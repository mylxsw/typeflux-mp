import '../core/environment.dart';

/// API tickets contain HTTP(S) origins; local HTTP needs the same Debug opt-in
/// as API requests before it can become an unencrypted WebSocket connection.
Uri realtimeWebSocketUri(
  String origin, {
  ApiOriginPolicy policy = ApiOriginPolicy.fromBuild,
}) {
  final uri = Uri.parse(origin);
  policy.validate(uri);
  return uri.replace(
    scheme: uri.scheme == 'http' ? 'ws' : 'wss',
    path: '/api/v1/asr/ws/default',
  );
}
