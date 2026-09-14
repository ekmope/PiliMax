import 'package:PiliPlus/services/audio_handler.dart';
import 'package:PiliPlus/services/audio_session.dart';
import 'package:PiliPlus/services/cdn_diagnostics_service.dart';
import 'package:PiliPlus/services/cdn_last_video_service.dart';
import 'package:PiliPlus/services/cdn_service.dart';
import 'package:PiliPlus/services/traffic_stats_service.dart';

VideoPlayerServiceHandler? videoPlayerServiceHandler;
AudioSessionHandler? audioSessionHandler;

Future<void> setupServiceLocator() async {
  final audio = await initAudioService();
  videoPlayerServiceHandler = audio;
  audioSessionHandler = AudioSessionHandler();
  await TrafficStatsService.instance.initialize();
  await CdnService.instance.initialize();
  await CdnDiagnosticsService.instance.initialize();
  await CdnLastVideoService.instance.initialize();
}
