import 'package:PiliMax/utils/path_utils.dart';
import 'package:path/path.dart' as path;

typedef CodecOpenErrorHandler = bool Function(String event);

sealed class DataSource {
  final String videoSource;
  final String? audioSource;
  final CodecOpenErrorHandler? onCodecOpenError;

  DataSource({
    required this.videoSource,
    required this.audioSource,
    this.onCodecOpenError,
  });
}

class NetworkSource extends DataSource {
  NetworkSource({
    required super.videoSource,
    required super.audioSource,
    super.onCodecOpenError,
  });
}

class FileSource extends DataSource {
  final String dir;
  final bool isMp4;

  FileSource({
    required this.dir,
    required this.isMp4,
    required bool hasDashAudio,
    required String typeTag,
  }) : super(
         videoSource: path.join(
           dir,
           typeTag,
           isMp4 ? PathUtils.videoNameType1 : PathUtils.videoNameType2,
         ),
         audioSource: isMp4 || !hasDashAudio
             ? null
             : path.join(dir, typeTag, PathUtils.audioNameType2),
       );
}
