import 'package:flutter/material.dart';
import '../models/anime.dart';

class AnimeDetailsScreen extends StatelessWidget {
  final Anime anime;

  const AnimeDetailsScreen({super.key, required this.anime});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(anime.title),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '放送局: ${anime.station}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '放送時間: ${anime.time}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            const Text('詳細情報がここに表示されます。'),
          ],
        ),
      ),
    );
  }
}