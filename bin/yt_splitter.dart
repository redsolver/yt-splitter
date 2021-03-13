import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart';
import 'package:xdg_directories/xdg_directories.dart';

void main(List<String> arguments) async {
  if (arguments.isEmpty) {
    stderr.writeln('Usage: yt-splitter <videoId> [directory]');
    exit(1);
  }

  var videoId = arguments[0];

  final uri = Uri.tryParse(videoId);

  if (uri != null) {
    if (uri.host == 'www.youtube.com') {
      videoId = uri.queryParameters['v'];
    } else if (uri.host == 'youtu.be') {
      videoId = uri.pathSegments.last;
    }
  }

  print('YT video: $videoId...');

  final path = join(
    // TODO Maybe fallback to /tmp
    Platform.isWindows ? Platform.environment['TMP'] : cacheHome.path,
    'yt-splitter',
    videoId,
  );

  Directory(path).createSync(recursive: true);

  final mp3FilePath = join(path, 'output.mp3');
  final jsonFilePath = join(path, 'output.info.json');
  // final thumbnailFilePath = join(path, 'output.jpg');

  if (!File(mp3FilePath).existsSync()) {
    print('Downloading and converting audio file from YouTube...');
    final process = await Process.start(
      'youtube-dl',
      [
        //'--add-metadata',
        //'--embed-thumbnail',
        //'--write-description',
        '--write-info-json',
        '--write-thumbnail',
        '--extract-audio',
        '--audio-format',
        'mp3',
        '--output',
        'output.%(ext)s',
        'https://www.youtube.com/watch?v=$videoId'
      ],
      workingDirectory: path,
    );

    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((event) {
      if (event.isNotEmpty) {
        print(event);
      }
    });

    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((event) {
      if (event.isNotEmpty) {
        stderr.writeln(event);
      }
    });

    var buildCode = await process.exitCode;

    if (buildCode != 0) throw 'YouTube-DL failed.';
  }

  final data = json.decode(File(jsonFilePath).readAsStringSync());

  final album = stripUnsafeCharacters(data['title']);

  final artist = data['artist'] ?? data['uploader'] ?? '';

  if ((data['chapters'] ?? []).isEmpty) {
    stderr.writeln(
        'Error: This video does not contain chapters. Just use youtube-dl instead.');
    exit(1);
  }

  final outputDirectoryPath =
      arguments.length == 2 ? join('${arguments[1]}', album) : album;

  print('Tracks will be saved to $outputDirectoryPath');

  Directory(outputDirectoryPath).createSync(recursive: true);

  int tracknumber = 0;

  print('Splitting mp3 file...');

  final alreadySeenTitles = <String>[];

  for (final chapter in data['chapters']) {
    var chapterTitle = chapter['title'];

    int i = 1;

    while (alreadySeenTitles.contains(chapterTitle)) {
      i++;
      chapterTitle = chapter['title'] + ' ($i)';
    }

    alreadySeenTitles.add(chapterTitle);

    chapterTitle = stripUnsafeCharacters(chapterTitle);

    tracknumber++;

    print('[splitting] $chapterTitle...');

    final startString = renderDuration(chapter['start_time'].round());
    final endString = renderDuration(chapter['end_time'].round());

/*     final thumbnailFlags = [
      '-i',
      thumbnailFilePath,
      '-map',
      '0:0',
      '-map',
      '1:0',
      '-codec',
      'copy',
      '-id3v2_version',
      '3',
      '-metadata:s:v',
      'title=Album cover',
      '-metadata:s:v',
      'comment=Cover (front)',
    ]; */

    final res = await Process.run('ffmpeg', [
      '-i',
      mp3FilePath,
      // ...thumbnailFlags,
      '-vn',
      '-acodec',
      'copy',
      '-ss',
      startString,
      '-to',
      endString,
      '-metadata',
      'title=$chapterTitle',
      '-metadata',
      'album=$album',
      '-metadata',
      'artist=$artist',
      '-metadata',
      'track=$tracknumber',
      '-y',
      'file:' + join(outputDirectoryPath, '$chapterTitle.mp3'),
    ]);
    if (res.exitCode != 0) {
      print('Error while converting mp3 file:');
      print(res.stdout);
      print(res.stderr);
    }
  }
}

String renderDuration(int x) {
  var secs = (x % 60).toString();
  if (secs.length == 1) secs = '0$secs';

  var mins = ((x % 3600) / 60).floor().toString();
  if (mins.length == 1) mins = '0$mins';

  var str = '$mins:$secs';

  if (x >= 3600) {
    str = '${(x / 3600).floor()}:$str';
  }
  return str;
}

String stripUnsafeCharacters(String text) {
  if (Platform.isLinux) {
    return text.trim().replaceAll('/', '_');
  } else if (Platform.isMacOS) {
    return text.trim().replaceAll(RegExp(r'[\/:]'), '_');
  } else {
    return text.trim().replaceAll(RegExp(r'[\|\/\\\?":\*<>]'), '_');
  }
}
