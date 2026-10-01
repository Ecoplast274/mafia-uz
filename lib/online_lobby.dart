import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import 'multiplayer_service.dart';

class OnlineLobbyPage extends StatefulWidget {
  const OnlineLobbyPage({super.key});

  @override
  State<OnlineLobbyPage> createState() => _OnlineLobbyPageState();
}

class _OnlineLobbyPageState extends State<OnlineLobbyPage> {
  final service = MultiplayerService.instance;
  final name = TextEditingController();
  final code = TextEditingController();
  int size = 8;
  String? roomId;
  Stream<OnlineRoom>? roomStream;
  bool busy = false;

  @override
  void dispose() {
    name.dispose();
    code.dispose();
    super.dispose();
  }

  void showError(Object error) {
    if (!mounted) return;
    final message = error is FirebaseFunctionsException
        ? (error.message ?? error.code)
        : error.toString().replaceFirst('Bad state: ', '');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> createRoom() async {
    if (name.text.trim().length < 2) {
      showError(StateError('Ism kamida 2 ta belgidan iborat bo‘lsin.'));
      return;
    }
    setState(() => busy = true);
    try {
      final id = await service.createRoom(size: size, name: name.text);
      setState(() {
        roomId = id;
        roomStream = service.watchRoom(id);
      });
    } catch (e) {
      showError(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> joinRoom() async {
    final id = code.text.trim().toUpperCase();
    if (id.length != 6 || name.text.trim().length < 2) {
      showError(StateError('6 belgili xona kodi va ism kiriting.'));
      return;
    }
    setState(() => busy = true);
    try {
      await service.joinRoom(roomId: id, name: name.text);
      setState(() {
        roomId = id;
        roomStream = service.watchRoom(id);
      });
    } catch (e) {
      showError(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> startGame(OnlineRoom room) async {
    setState(() => busy = true);
    try {
      await service.startGame(room.roomId);
    } catch (e) {
      showError(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> leaveRoom() async {
    final id = roomId;
    if (id == null) {
      if (mounted) Navigator.pop(context);
      return;
    }
    setState(() => busy = true);
    try {
      await service.leaveRoom(id);
    } catch (_) {
      // Local navigation still works if the network is already gone.
    } finally {
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!service.configured && roomId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Online multiplayer')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Firebase client konfiguratsiyasi hali tayyor emas.\n\n'
              'Backend tayyor. Android va Web Firebase app ro‘yxatdan '
              'o‘tkazilib, client FirebaseOptions berilgach bu ekran real '
              'xonalarga ulanadi.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Online multiplayer'),
        actions: [
          if (roomId != null)
            IconButton(
              onPressed: busy ? null : leaveRoom,
              icon: const Icon(Icons.exit_to_app),
            ),
        ],
      ),
      body: roomStream == null ? joinCreate() : lobby(),
    );
  }

  Widget joinCreate() => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: name,
            maxLength: 20,
            decoration: const InputDecoration(
              labelText: 'O‘yinchi ismi',
              prefixIcon: Icon(Icons.person),
            ),
          ),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 8, label: Text('8'), icon: Icon(Icons.groups)),
              ButtonSegment(value: 12, label: Text('12'), icon: Icon(Icons.groups_3)),
            ],
            selected: {size},
            onSelectionChanged:
                busy ? null : (v) => setState(() => size = v.first),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: busy ? null : createRoom,
            icon: const Icon(Icons.add_circle),
            label: const Text('Yangi xona yaratish'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: code,
            maxLength: 6,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Xona kodi',
              prefixIcon: Icon(Icons.key),
            ),
          ),
          FilledButton.icon(
            onPressed: busy ? null : joinRoom,
            icon: const Icon(Icons.login),
            label: const Text('Xonaga qo‘shilish'),
          ),
        ],
      );

  Widget lobby() => StreamBuilder<OnlineRoom>(
        stream: roomStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Lobby xatosi: ' + snapshot.error.toString()));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final room = snapshot.data!;
          final isHost = room.hostUid == service.currentUid;

          if (!room.isLobby) {
            return Center(
              child: Text(
                'O‘yin boshlandi: ' + room.phase,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    children: [
                      const Text('XONA KODI',
                          style: TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      SelectableText(
                        room.roomId,
                        style: const TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 7,
                        ),
                      ),
                      Text(room.players.length.toString() + '/' +
                          room.size.toString() + ' o‘yinchi'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              for (final player in room.players)
                ListTile(
                  leading: CircleAvatar(child: Text((player.seat + 1).toString())),
                  title: Text(player.name),
                  trailing: player.uid == room.hostUid
                      ? const Icon(Icons.star, color: Colors.amber)
                      : null,
                ),
              const SizedBox(height: 12),
              if (isHost)
                FilledButton.icon(
                  onPressed: busy || room.players.length != room.size
                      ? null
                      : () => startGame(room),
                  icon: const Icon(Icons.play_arrow),
                  label: Text(
                    room.players.length == room.size
                        ? 'O‘yinni boshlash'
                        : 'Avval xona to‘lsin',
                  ),
                )
              else
                const Center(
                  child: Text('Yetakchi xona to‘lishini kutmoqda.'),
                ),
            ],
          );
        },
      );
}
