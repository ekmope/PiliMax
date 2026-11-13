/// Keep query parameters intact when requesting the canonical directory URL.
Uri redirectRequestUri(String url) {
  // Search accepts a pasted b23.tv link without a scheme. Ordinary search
  // text must never become a relative request against Dio's API base URL.
  final normalized = url.startsWith('//')
      ? 'https:$url'
      : RegExp(r'^b23\.tv/', caseSensitive: false).hasMatch(url)
      ? 'https://$url'
      : url;
  final uri = Uri.parse(normalized);
  if ((uri.scheme != 'http' && uri.scheme != 'https') || uri.host.isEmpty) {
    throw const FormatException('Expected an HTTP link');
  }
  return uri.path.endsWith('/') ? uri : uri.replace(path: '${uri.path}/');
}
