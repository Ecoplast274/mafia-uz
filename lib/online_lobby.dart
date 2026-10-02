import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import 'online_game.dart';
import 'online_service.dart';

class OnlineLobbyPage extends StatefulWidget {
  const OnlineLobbyPage({super.key});

  @override
  State<OnlineLobbyPage> createState() => _OnlineLobbyPageState();
}

class _OnlineLobbyPageState extends State<OnlineLobbyPage> {
  final service = MafiaOnlineService.instance;
  final name = TextEditingController();
  final code = TextEditingController();
  int size = 8;
  String? roomId;
  Stream<dynamic>? roomStream;
  bool busy = false;
  bool initializing = true;
  String? initError;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final ok = await service.initialize();
    if (!mounted) return;
    setState(() {
      initializing = false;
      initError = ok ? null : service.initError;
    });
  }

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
      await service.initialize();
      final id = await service.createRoom(size: size, name: name.text);
      setState(() {
        roomId = id;
        roomStream = service.roomStream(id);
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
      await service.initialize();
      await service.joinRoom(roomId: id, name: name.text);
      setState(() {
        roomId = id;
        roomStream = service.roomStream(id);
      });
    } catch (e) {
      showError(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> startGame(String id) async {
    setState(() => busy = true);
    try {
      await service.startGame(id);
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
    if (initializing) {
      return const Scaffold(
        appBar: AppBar(title: Text('Online multiplayer')),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (initError != null && roomId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Online multiplayer')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Firebase ulanishi tayyor emas.\\n\\n$initError',
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

  Widget lobby() => StreamBuilder<dynamic>(
        stream: roomStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Lobby xatosi: ' + snapshot.error.toString()));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final snap = snapshot.data as dynamic;
          if (!snap.exists) {
            return const Center(child: Text('Xona topilmadi.'));
          }
          final data = snap.data() as Map<String, dynamic>;
          final roomIdValue = (data['roomId'] ?? roomId ?? '').toString();
          final phase = (data['phase'] ?? 'lobby').toString();
          final roomSize = (data['size'] as num?)?.toInt() ?? size;
          final hostUid = data['hostUid']?.toString();
          final isHost = hostUid == service.user?.uid;

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: service.playersStream(roomIdValue),
            builder: (context, playersSnapshot) {
              if (playersSnapshot.hasError) {
                return Center(child: Text('O‘yinchilar xatosi: ${playersSnapshot.error}'));
              }
              if (!playersSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final players = playersSnapshot.data!.docs;

              if (phase != 'lobby') {
                return OnlineGamePage(roomId: roomIdValue);
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
                        roomIdValue,
                        style: const TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 7,
                        ),
                      ),
                      Text(players.length.toString() + '/' +
                          roomSize.toString() + ' o‘yinchi'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              for (final player in players)
                ListTile(
                  leading: CircleAvatar(child: Text((((player.data()['seat'] as num?)?.toInt() ?? 0) + 1).toString())),
                  title: Text((player.data()['name'] ?? player.id).toString()),
                  trailing: player.id == hostUid
                      ? const Icon(Icons.star, color: Colors.amber)
                      : null,
                ),
              const SizedBox(height: 12),
              if (isHost)
                FilledButton.icon(
                  onPressed: busy || players.length != roomSize
                      ? null
                      : () => startGame(roomIdValue),
                  icon: const Icon(Icons.play_arrow),
                  label: Text(
                    players.length == roomSize
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
        },
      );
}
