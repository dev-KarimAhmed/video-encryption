import 'dart:io';
import 'dart:developer' as dev;
import 'package:better_player/better_player.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: VideoPlayerScreen(
        videoUrl:
            'https://umszdjphnixokwvykjti.supabase.co/storage/v1/object/public/slider_videos/English_PREP%203_Mostafa%20Gad_Unit%201_Part%201_Homework.mp4?t=2024-08-14T10%3A46%3A21.848Z',
      ),
    );
  }
}

class VideoPlayerScreen extends StatefulWidget {
  final String videoUrl;

  const VideoPlayerScreen({super.key, required this.videoUrl});

  @override
  _VideoPlayerScreenState createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  BetterPlayerController? _betterPlayerController;
  bool _isDownloading = false;
  bool _isDownloaded = false;
  double _downloadProgress = 0.0;
  String _playSource = "Loading...";
  String? _localVideoPath;
  Dio _dio = Dio();
  CancelToken? _cancelToken;
  int _downloadedBytes = 0;
  bool _isPaused = false;

  @override
  void initState() {
    super.initState();
    _initializeBetterPlayer();
  }

  Future<void> _initializeBetterPlayer() async {
    final directory = await getApplicationDocumentsDirectory();
    final filePath = '${directory.path}/${widget.videoUrl.split('/').last}';
    final file = File(filePath);

    try {
      if (await file.exists()) {
        if (await _isFullVideoDownloaded(filePath)) {
          _playSource = "Playing from Storage";
          _betterPlayerController = BetterPlayerController(
            const BetterPlayerConfiguration(),
            betterPlayerDataSource: BetterPlayerDataSource(
              BetterPlayerDataSourceType.file,
              filePath,
            ),
          );
        } else {
          _playSource = "Error: Incomplete Video";
        }
      } else {
        _playSource = "Playing Online";
        _betterPlayerController = BetterPlayerController(
          const BetterPlayerConfiguration(),
          betterPlayerDataSource: BetterPlayerDataSource(
            BetterPlayerDataSourceType.network,
            widget.videoUrl,
          ),
        );
      }
    } catch (e) {
      dev.log('Error initializing video player: $e');
      _playSource = "Error initializing video";
    }

    setState(() {
      _isDownloaded = file.existsSync();
    });
  }

  Future<bool> _isFullVideoDownloaded(String filePath) async {
    final file = File(filePath);
    if (await file.exists()) {
      final expectedFileSize = await _getRemoteFileSize(widget.videoUrl);
      final localFileSize = await file.length();
      return localFileSize >= expectedFileSize;
    }
    return false;
  }

  Future<int> _getRemoteFileSize(String url) async {
    try {
      final response = await Dio().head(url);
      return int.parse(response.headers.value('content-length')!);
    } catch (e) {
      dev.log('Error getting remote file size: $e');
      return 0;
    }
  }

  Future<void> _downloadVideo({bool resume = false}) async {
    setState(() {
      _isDownloading = true;
      _cancelToken = CancelToken();
    });

    try {
      final directory = await getApplicationDocumentsDirectory();
      final filePath = '${directory.path}/${widget.videoUrl.split('/').last}';
      final file = File(filePath);

      if (resume && await file.exists()) {
        _downloadedBytes = await file.length();
      }

      await _dio.download(
        widget.videoUrl,
        filePath,
        cancelToken: _cancelToken,
        onReceiveProgress: (received, total) {
          setState(() {
            _downloadProgress = (_downloadedBytes + received) / total;
          });
        },
        options: Options(
          headers: resume && _downloadedBytes > 0
              ? {'range': 'bytes=$_downloadedBytes-'}
              : null,
        ),
      );

      if (await _isFullVideoDownloaded(filePath)) {
        setState(() {
          _isDownloading = false;
          _isDownloaded = true;
          _playSource = "Playing from Storage";
          _localVideoPath = filePath;
          dev.log('Downloaded video path: $filePath');
          _initializeBetterPlayer(); // Reinitialize to play the downloaded video
        });
      } else {
        dev.log('Downloaded file is incomplete');
        setState(() {
          _isDownloading = false;
          _isDownloaded = false;
          _playSource = "Error: Incomplete Video";
        });
      }
    } catch (e) {
      if (CancelToken.isCancel(e as DioException)) {
        dev.log('Download canceled');
      } else {
        dev.log('Error downloading video: $e');
      }
      setState(() {
        _isDownloading = false;
      });
    }
  }

  void _pauseDownload() {
    _cancelToken?.cancel();
    setState(() {
      _isPaused = true;
    });
  }

  void _resumeDownload() {
    setState(() {
      _isPaused = false;
      _downloadVideo(resume: true);
    });
  }

  void _cancelDownload() {
    _cancelToken?.cancel();
    setState(() {
      _isDownloading = false;
      _downloadProgress = 0.0;
      _downloadedBytes = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: _betterPlayerController != null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(_playSource),
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: BetterPlayer(controller: _betterPlayerController!),
                  ),
                  if (_isDownloading)
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: LinearProgressIndicator(
                        value: _downloadProgress,
                        backgroundColor: Colors.grey[200],
                        color: Colors.blue,
                        minHeight: 5,
                      ),
                    ),
                  if (!_isDownloaded && !_isDownloading)
                    ElevatedButton(
                      onPressed: _downloadVideo,
                      child: const Text('Download Video'),
                    ),
                  if (_isDownloading) ...[
                    ElevatedButton(
                      onPressed: _isPaused ? _resumeDownload : _pauseDownload,
                      child: Text(_isPaused ? 'Resume Download' : 'Pause Download'),
                    ),
                    ElevatedButton(
                      onPressed: _cancelDownload,
                      child: const Text('Cancel Download'),
                    ),
                    Text('${(_downloadProgress * 100).toStringAsFixed(0)}%'),
                  ],
                ],
              )
            : const CircularProgressIndicator(), // Circular progress indicator until initialization
      ),
    );
  }

  @override
  void dispose() {
    _betterPlayerController?.dispose();
    super.dispose();
  }
}
