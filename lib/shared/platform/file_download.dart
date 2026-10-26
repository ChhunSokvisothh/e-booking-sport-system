import 'file_download_stub.dart'
    if (dart.library.html) 'file_download_web.dart' as impl;

Future<bool> downloadBytes({
  required String fileName,
  required List<int> bytes,
  required String mimeType,
}) {
  return impl.downloadBytes(fileName: fileName, bytes: bytes, mimeType: mimeType);
}
