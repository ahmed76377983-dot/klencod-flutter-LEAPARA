// LEAPARA - bright cartoon platformer. Package: com.ahmedhosam.leapara
// pubspec deps: shared_preferences ^2.3.2, audioplayers ^5.2.1,
//               flutter_local_notifications ^15.1.3, timezone ^0.9.2
// AndroidManifest: add <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tzdata;

// Logical height; logical width adapts to the real aspect ratio (no black bars).
const double kH = 540;
const double kGroundTop = 430; // y where the grass starts in most levels

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const LeaparaApp());
}

class LeaparaApp extends StatelessWidget {
  const LeaparaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LEAPARA',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.light(useMaterial3: true),
      home: const BootScreen(),
    );
  }
}

// ---------- Image assets ----------
class Art {
  static final Map<String, ui.Image> imgs = {};

  static const List<String> files = [
    'sky.jpg', 'mountains.png', 'hills.png',
    'idle_0.png', 'idle_1.png', 'idle_2.png', 'idle_3.png',
    'run_0.png', 'run_1.png', 'run_2.png', 'run_3.png', 'run_4.png', 'run_5.png',
    'jump_0.png', 'jump_1.png', 'jump_2.png',
    'fall_0.png', 'fall_1.png',
    'hurt_0.png', 'hurt_1.png',
    'snail_0.png', 'snail_1.png',
    'mushroom_0.png', 'mushroom_1.png', 'mushroom_2.png', 'mushroom_3.png',
    'turtle_0.png', 'turtle_1.png',
    'slime_0.png', 'slime_1.png',
    'coin_0.png', 'coin_1.png', 'coin_2.png', 'coin_3.png', 'coin_4.png', 'coin_5.png',
    'heart.png', 'gem.png', 'star.png',
    'ground.png', 'platform.png', 'crate.png', 'spikes.png',
    'bush.png', 'flowers.png', 'grass.png', 'mushroom.png', 'sign.png',
    'zuzu.png', 'zip.png', 'tuff.png', 'skye.png', 'bolt.png',
    'logo.png', 'btn_play.png', 'btn_store.png', 'btn_achievements.png', 'btn_settings.png', 'chest_daily.png',
  ];

  static Future<void> load() async {
    await Future.wait(files.map(_load));
  }

  static Future<void> _load(String path) async {
    final data = await rootBundle.load('assets/$path');
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    imgs[path] = frame.image;
  }

  static ui.Image get(String path) => imgs[path]!;
}

// ---------- Sound effects ----------
class Sfx {
  static bool muted = false;
  static const List<String> names = [
    'jump', 'land', 'coin', 'stomp', 'hurt', 'checkpoint',
    'win', 'gem', 'star', 'click', 'chest', 'powerup',
  ];
  static final Map<String, AudioPlayer> _players = {};

  static Future<void> init() async {
    for (final n in names) {
      final p = AudioPlayer();
      try {
        await p.setPlayerMode(PlayerMode.lowLatency);
        await p.setSource(AssetSource('$n.ogg'));
        _players[n] = p;
      } catch (_) {}
    }
  }

  static void play(String name, {double volume = 1.0}) {
    if (muted) return;
    final p = _players[name];
    if (p == null) return;
    unawaited(() async {
      try {
        await p.stop();
        await p.play(AssetSource('$name.ogg'), volume: volume);
      } catch (_) {}
    }());
  }
}

// ---------- Local notifications (daily reward + come-back reminder) ----------
class Notifier {
  static final FlutterLocalNotificationsPlugin _p = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static Future<void> init() async {
    try {
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      );
      await _p.initialize(settings);
      // Android 13+ runtime permission (safe no-op on older versions)
      final android = _p.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestPermission();
      try {
        tzdata.initializeTimeZones();
        tz.setLocalLocation(tz.getLocation('Africa/Cairo'));
      } catch (_) {}
      _ready = true;
      await _scheduleDailyReward();
    } catch (_) {}
  }

  static NotificationDetails _details() => const NotificationDetails(
        android: AndroidNotificationDetails(
          'leapara_rewards',
          'Leapara Rewards',
          channelDescription: 'Daily rewards and friendly reminders from LEAPARA',
          importance: Importance.high,
          priority: Priority.high,
        ),
      );

  static Future<void> _scheduleDailyReward() async {
    if (!_ready) return;
    try {
      await _p.periodicallyShow(
        1,
        'DAILY REWARD READY!',
        'Your free chest is waiting in LEAPARA. Come claim it!',
        RepeatInterval.daily,
        _details(),
        androidAllowWhileIdle: false,
      );
    } catch (_) {}
  }

  // Called when the app goes to background: remind after 2 days away.
  static Future<void> scheduleComeback() async {
    if (!_ready) return;
    try {
      final now = tz.TZDateTime.now(tz.local);
      await _p.zonedSchedule(
        2,
        'Kai misses you!',
        'Come back for a run - your coins and chest are waiting.',
        now.add(const Duration(hours: 48)),
        _details(),
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        androidAllowWhileIdle: false,
      );
    } catch (_) {}
  }

  static Future<void> cancelAll() async {
    try {
      await _p.cancelAll();
    } catch (_) {}
  }

  // Called when the app comes back to foreground.
  static Future<void> cancelComeback() async {
    if (!_ready) return;
    try {
      await _p.cancel(2);
      await _scheduleDailyReward(); // refresh the daily timer
    } catch (_) {}
  }
}

// ---------- Save data ----------
class SaveData {
  static const String _kBlob = 'lp_save';

  int coins = 0;
  int unlockedLevel = 1;
  List<int> stars = [0, 0, 0, 0]; // stars collected per level (0/1)
  Set<String> awards = {};
  Set<String> owned = {'kai'};
  String character = 'kai';
  String lastChest = ''; // yyyy-mm-dd of the last daily chest claim
  bool notifications = true;

  static Future<SaveData> load() async {
    final s = SaveData();
    try {
      final p = await SharedPreferences.getInstance();
      final blob = p.getString(_kBlob);
      if (blob != null) {
        final m = jsonDecode(blob) as Map<String, dynamic>;
        s.coins = (m['coins'] as num?)?.toInt() ?? 0;
        s.unlockedLevel = ((m['unlockedLevel'] as num?)?.toInt() ?? 1).clamp(1, kLevels.length);
        final st = (m['stars'] as List?)?.map((e) => (e as num).toInt()).toList();
        if (st != null && st.length == 4) s.stars = st;
        s.awards = Set<String>.from((m['awards'] as List?)?.map((e) => '$e') ?? []);
        s.owned = Set<String>.from((m['owned'] as List?)?.map((e) => '$e') ?? ['kai']);
        s.character = '${m['character'] ?? 'kai'}';
        s.lastChest = '${m['lastChest'] ?? ''}';
        s.notifications = m['notifications'] != false;
        Sfx.muted = m['muted'] == true;
      }
      s.owned.add('kai');
      if (!s.owned.contains(s.character)) s.character = 'kai';
    } catch (_) {}
    return s;
  }

  Future<void> save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kBlob, jsonEncode({
        'coins': coins,
        'unlockedLevel': unlockedLevel,
        'stars': stars,
        'awards': awards.toList(),
        'owned': owned.toList(),
        'character': character,
        'lastChest': lastChest,
        'notifications': notifications,
        'muted': Sfx.muted,
      }));
    } catch (_) {}
  }

  bool get chestAvailable {
    final now = DateTime.now();
    final today = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    return lastChest != today;
  }

  Future<void> claimChest() async {
    final now = DateTime.now();
    lastChest = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    coins += 75;
    await save();
  }
}

// ---------- Roster ----------
class CharDef {
  final String id;
  final String name;
  final int price;
  final String ability;
  final String desc;
  const CharDef(this.id, this.name, this.price, this.ability, this.desc);
}

const List<CharDef> kRoster = [
  CharDef('kai', 'Kai', 0, 'Balanced', 'The hero of LEAPARA. Good at everything.'),
  CharDef('zuzu', 'Zuzu', 800, 'HIGH JUMP', 'Jumps 15% higher than anyone.'),
  CharDef('zip', 'Zip', 800, 'SPEED', 'Runs 25% faster.'),
  CharDef('tuff', 'Tuff', 1200, 'SHIELD', 'Blocks one hit per checkpoint.'),
  CharDef('skye', 'Skye', 1500, 'GLIDE', 'Hold JUMP in the air to glide down slowly.'),
  CharDef('bolt', 'Bolt', 2000, 'COIN MAGNET', 'Nearby coins fly to him.'),
];

// Ability modifiers derived from the selected character
class HeroAbility {
  final double jumpMul;
  final double runMul;
  final bool shield;
  final bool glide;
  final bool magnet;
  const HeroAbility({
    this.jumpMul = 1.0,
    this.runMul = 1.0,
    this.shield = false,
    this.glide = false,
    this.magnet = false,
  });

  static HeroAbility of(String id) {
    switch (id) {
      case 'zuzu':
        return const HeroAbility(jumpMul: 1.15);
      case 'zip':
        return const HeroAbility(runMul: 1.25);
      case 'tuff':
        return const HeroAbility(shield: true);
      case 'skye':
        return const HeroAbility(glide: true);
      case 'bolt':
        return const HeroAbility(magnet: true);
      default:
        return const HeroAbility();
    }
  }
}

// ---------- Level data ----------
class Solid {
  final double x, y, w, h; // top-left + size, fully solid
  const Solid(this.x, this.y, this.w, this.h);
}

class Plat {
  final double x, y, w; // one-way platform: land from above only
  const Plat(this.x, this.y, this.w);
}

class SpikeStrip {
  final double x, baseY, w; // spikes sit on baseY (a floor top)
  const SpikeStrip(this.x, this.baseY, this.w);
}

class EnemySpawn {
  final String type; // snail | mushroom | turtle | slime
  final double x, y; // feet position
  const EnemySpawn(this.type, this.x, this.y);
}

class LevelDef {
  final String name;
  final double width;
  final List<Solid> grounds;
  final List<Plat> platforms;
  final List<Solid> crates;
  final List<SpikeStrip> spikes;
  final List<Offset> coins;
  final List<Offset> hearts;
  final List<Offset> gems;
  final Offset star;
  final List<EnemySpawn> enemies;
  final List<double> checkpoints;
  final double flagX;

  const LevelDef({
    required this.name,
    required this.width,
    required this.grounds,
    this.platforms = const [],
    this.crates = const [],
    this.spikes = const [],
    required this.coins,
    this.hearts = const [],
    this.gems = const [],
    required this.star,
    required this.enemies,
    required this.checkpoints,
    required this.flagX,
  });
}

List<Offset> coinRow(double x, double y, int n, [double step = 46]) =>
    List.generate(n, (i) => Offset(x + i * step, y));

List<Offset> coinArc(double x, double y, int n, [double step = 44, double lift = 34]) {
  return List.generate(n, (i) {
    final t = n == 1 ? 0.0 : (i / (n - 1)) * 2 - 1; // -1..1
    return Offset(x + i * step, y - (1 - t * t) * lift);
  });
}

const double g = kGroundTop;

final List<LevelDef> kLevels = [
  // ---------------- Level 1: Sunny Start (tutorial) ----------------
  LevelDef(
    name: 'Sunny Start',
    width: 3400,
    grounds: [
      Solid(0, g, 1200, kH - g),
      Solid(1290, g, 820, kH - g),
      Solid(2230, g, 1170, kH - g),
    ],
    platforms: const [
      Plat(880, 330, 170),
      Plat(1420, 325, 170),
      Plat(2360, 320, 170),
      Plat(2620, 245, 160),
      Plat(2870, 240, 150),
    ],
    spikes: const [SpikeStrip(2450, g, 96)],
    coins: [
      ...coinRow(320, 380, 4),
      ...coinArc(1180, 360, 4),
      ...coinRow(900, 290, 3),
      ...coinRow(1440, 285, 3),
      ...coinRow(1500, 380, 4),
      ...coinArc(2090, 360, 4),
      ...coinRow(2380, 280, 3),
      ...coinRow(2640, 205, 3),
      ...coinRow(3000, 380, 4),
    ],
    hearts: const [Offset(2060, 390)],
    gems: const [Offset(965, 288), Offset(2695, 205)],
    star: const Offset(2945, 200),
    enemies: const [
      EnemySpawn('snail', 700, g),
      EnemySpawn('snail', 1600, g),
      EnemySpawn('mushroom', 2500, g),
    ],
    checkpoints: const [1350, 2260],
    flagX: 3280,
  ),
  // ---------------- Level 2: Mushroom Hills ----------------
  LevelDef(
    name: 'Mushroom Hills',
    width: 3800,
    grounds: [
      Solid(0, g, 900, kH - g),
      Solid(1000, g, 700, kH - g),
      Solid(1800, g, 700, kH - g),
      Solid(2600, g, 1200, kH - g),
      Solid(600, 320, 120, 110), // grassy ledge
      Solid(1900, 300, 130, 130),
    ],
    platforms: const [
      Plat(920, 330, 150),
      Plat(1150, 260, 160),
      Plat(1750, 320, 150),
      Plat(2150, 300, 170),
      Plat(2520, 330, 150),
      Plat(2850, 260, 170),
      Plat(3150, 200, 150),
    ],
    spikes: const [SpikeStrip(1400, g, 110), SpikeStrip(3000, g, 96)],
    coins: [
      ...coinRow(200, 380, 4),
      ...coinArc(900, 350, 4),
      ...coinRow(1170, 220, 3),
      ...coinRow(1400, 360, 3),
      ...coinArc(1700, 350, 4),
      ...coinRow(2170, 260, 3),
      ...coinRow(2870, 220, 3),
      ...coinRow(3170, 160, 3),
      ...coinRow(3400, 380, 4),
    ],
    hearts: const [Offset(2550, 380)],
    gems: const [Offset(660, 270), Offset(1965, 250)],
    star: const Offset(3225, 150),
    enemies: const [
      EnemySpawn('mushroom', 500, g),
      EnemySpawn('snail', 1300, g),
      EnemySpawn('mushroom', 2000, g),
      EnemySpawn('mushroom', 2800, g),
      EnemySpawn('snail', 3300, g),
    ],
    checkpoints: const [1050, 2650],
    flagX: 3680,
  ),
  // ---------------- Level 3: Turtle Pass ----------------
  LevelDef(
    name: 'Turtle Pass',
    width: 4000,
    grounds: [
      Solid(0, g, 800, kH - g),
      Solid(900, g, 600, kH - g),
      Solid(1600, g, 500, kH - g),
      Solid(2200, g, 600, kH - g),
      Solid(2900, g, 1100, kH - g),
    ],
    platforms: const [
      Plat(820, 320, 140),
      Plat(1050, 250, 150),
      Plat(1520, 300, 140),
      Plat(2120, 310, 150),
      Plat(2450, 250, 160),
      Plat(2820, 300, 140),
      Plat(3150, 230, 160),
    ],
    crates: const [
      Solid(1700, g - 64, 64, 64),
      Solid(1764, g - 64, 64, 64),
      Solid(1732, g - 128, 64, 64),
      Solid(3300, g - 64, 64, 64),
    ],
    spikes: const [SpikeStrip(1200, g, 128), SpikeStrip(2300, g, 110), SpikeStrip(3600, g, 96)],
    coins: [
      ...coinRow(250, 380, 4),
      ...coinArc(800, 350, 4),
      ...coinRow(1070, 210, 3),
      ...coinArc(1500, 340, 4),
      ...coinRow(1730, g - 190, 2),
      ...coinArc(2100, 350, 4),
      ...coinRow(2470, 210, 3),
      ...coinArc(2800, 340, 4),
      ...coinRow(3170, 190, 3),
      ...coinRow(3750, 380, 3),
    ],
    hearts: const [Offset(1650, 380), Offset(3350, 380)],
    gems: const [Offset(1125, 205), Offset(2525, 205)],
    star: const Offset(3230, 175),
    enemies: const [
      EnemySpawn('turtle', 550, g),
      EnemySpawn('snail', 1100, g),
      EnemySpawn('turtle', 1900, g),
      EnemySpawn('mushroom', 2400, g),
      EnemySpawn('turtle', 3100, g),
      EnemySpawn('mushroom', 3500, g),
    ],
    checkpoints: const [1650, 2950],
    flagX: 3900,
  ),
  // ---------------- Level 4: Slime Summit ----------------
  LevelDef(
    name: 'Slime Summit',
    width: 4200,
    grounds: [
      Solid(0, g, 700, kH - g),
      Solid(800, g, 500, kH - g),
      Solid(1400, g, 450, kH - g),
      Solid(1950, g, 450, kH - g),
      Solid(2500, g, 500, kH - g),
      Solid(3100, g, 1100, kH - g),
      Solid(900, 300, 120, 130),
      Solid(2050, 280, 130, 150),
      Solid(3300, 300, 120, 130),
    ],
    platforms: const [
      Plat(720, 330, 140),
      Plat(1080, 230, 150),
      Plat(1330, 320, 140),
      Plat(1880, 310, 140),
      Plat(2430, 300, 150),
      Plat(2750, 230, 150),
      Plat(3030, 320, 140),
      Plat(3500, 220, 170),
      Plat(3750, 160, 150),
    ],
    spikes: const [SpikeStrip(1500, g, 110), SpikeStrip(2600, g, 110), SpikeStrip(3900, g, 96)],
        coins: [
      ...coinRow(220, 380, 4),
      ...coinArc(700, 350, 4),
      ...coinRow(1100, 190, 3),
      ...coinArc(1350, 340, 4),
      ...coinRow(1900, 270, 3),
      ...coinArc(2400, 340, 4),
      ...coinRow(2770, 190, 3),
      ...coinArc(3000, 340, 4),
      ...coinRow(3520, 180, 3),
      ...coinRow(3150, 380, 4),
    ],
    hearts: const [Offset(1450, 380), Offset(3150, 380)],
    gems: const [Offset(960, 255), Offset(2115, 235), Offset(3360, 255)],
    star: const Offset(3825, 110),
    enemies: const [
      EnemySpawn('slime', 500, g),
      EnemySpawn('mushroom', 1000, g),
      EnemySpawn('slime', 1600, g),
      EnemySpawn('turtle', 2200, g),
      EnemySpawn('slime', 2700, g),
      EnemySpawn('mushroom', 3300, g),
      EnemySpawn('slime', 3600, g),
    ],
    checkpoints: const [1450, 3150],
    flagX: 4100,
  ),
];

// ---------- Boot screen: loads art, sound, save, notifications ----------
class BootScreen extends StatefulWidget {
  const BootScreen({super.key});
  @override
  State<BootScreen> createState() => _BootState();
}

class _BootState extends State<BootScreen> {
  double _progress = 0;
  String _step = 'Waking up Kai...';

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      setState(() { _step = 'Painting the world...'; _progress = 0.15; });
      await Art.load();
      setState(() { _step = 'Tuning the sounds...'; _progress = 0.6; });
      await Sfx.init();
      setState(() { _step = 'Opening your save...'; _progress = 0.8; });
      final save = await SaveData.load();
      setState(() { _step = 'Setting reminders...'; _progress = 0.9; });
      await Notifier.init();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => MenuScreen(save: save)),
      );
    } catch (e) {
      setState(() { _step = 'Something went wrong: $e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF7EC8F7),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('assets/logo.png', width: 320, errorBuilder: (_, __, ___) => const Text('LEAPARA', style: TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: Colors.white))),
            const SizedBox(height: 40),
            SizedBox(
              width: 240,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: LinearProgressIndicator(
                  value: _progress,
                  minHeight: 14,
                  backgroundColor: Colors.white38,
                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFFC93C)),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(_step, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

// ---------- Tappable image button with press bounce ----------
class ImgBtn extends StatefulWidget {
  final String asset;
  final VoidCallback onTap;
  final double height;
  const ImgBtn({super.key, required this.asset, required this.onTap, this.height = 62});

  @override
  State<ImgBtn> createState() => _ImgBtnState();
}

class _ImgBtnState extends State<ImgBtn> {
  bool _down = false;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: () {
        Sfx.play('click');
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _down ? 0.9 : 1.0,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOutBack,
        child: Image.asset(widget.asset, height: widget.height, fit: BoxFit.contain),
      ),
    );
  }
}

// ---------- Menu / title screen ----------
class MenuScreen extends StatefulWidget {
  final SaveData save;
  const MenuScreen({super.key, required this.save});
  @override
  State<MenuScreen> createState() => _MenuState();
}

class _MenuState extends State<MenuScreen> with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late final AnimationController _bob;
  SaveData get save => widget.save;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bob = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _bob.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && save.notifications) {
      Notifier.scheduleComeback();
    } else if (state == AppLifecycleState.resumed) {
      Notifier.cancelComeback();
    }
  }

  Future<void> _claimChest() async {
    if (!save.chestAvailable) return;
    await save.claimChest();
    Sfx.play('chest');
    if (mounted) setState(() {});
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('+75 coins! Come back tomorrow for more.'),
        duration: Duration(seconds: 2),
      ));
    }
  }

  Widget _coinPill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white54, width: 2),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Image.asset('assets/coin_0.png', height: 26),
        const SizedBox(width: 8),
        Text('${save.coins}', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
      ]),
    );
  }

  Widget _charOnStage() {
    final id = save.character;
    final img = id == 'kai' ? 'assets/idle_0.png' : 'assets/$id.png';
    return AnimatedBuilder(
      animation: _bob,
      builder: (_, child) {
        final dy = -6 * _bob.value;
        final tilt = 0.02 * (_bob.value - 0.5);
        return Transform.translate(
          offset: Offset(0, dy),
          child: Transform.rotate(angle: tilt, child: child),
        );
      },
      child: Image.asset(img, height: 190, fit: BoxFit.contain),
    );
  }

  Widget _chest() {
    final ready = save.chestAvailable;
    return GestureDetector(
      onTap: ready ? _claimChest : null,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        AnimatedBuilder(
          animation: _bob,
          builder: (_, child) => Transform.scale(
            scale: ready ? 1.0 + 0.05 * _bob.value : 1.0,
            child: child,
          ),
          child: ColorFiltered(
            colorFilter: ready
                ? const ColorFilter.mode(Colors.transparent, BlendMode.multiply)
                : const ColorFilter.mode(Colors.grey, BlendMode.saturation),
            child: Image.asset('assets/chest_daily.png', height: 92),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          ready ? 'FREE CHEST!' : 'Come back tomorrow',
          style: TextStyle(
            color: ready ? const Color(0xFFFFF176) : Colors.white70,
            fontSize: 13,
            fontWeight: FontWeight.w800,
            shadows: const [Shadow(color: Colors.black45, blurRadius: 3)],
          ),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(fit: StackFit.expand, children: [
        // bright world background
        Image.asset('assets/sky.jpg', fit: BoxFit.cover),
        Align(alignment: Alignment.bottomCenter, child: Image.asset('assets/mountains.png', fit: BoxFit.fitWidth, alignment: Alignment.bottomCenter)),
        Align(alignment: Alignment.bottomCenter, child: Image.asset('assets/hills.png', fit: BoxFit.fitWidth, alignment: Alignment.bottomCenter)),
        Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            height: 90,
            width: double.infinity,
            child: Image.asset('assets/ground.png', repeat: ImageRepeat.repeatX, fit: BoxFit.none, alignment: Alignment.topLeft),
          ),
        ),
        // logo
        Align(
          alignment: const Alignment(0, -0.78),
          child: Image.asset('assets/logo.png', width: 340),
        ),
        // buttons, center-right
        Align(
          alignment: const Alignment(0.42, 0.05),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ImgBtn(asset: 'assets/btn_play.png', height: 88, onTap: () async {
              await Navigator.of(context).push(MaterialPageRoute(builder: (_) => LevelSelectScreen(save: save)));
              setState(() {});
            }),
            const SizedBox(height: 10),
            Row(mainAxisSize: MainAxisSize.min, children: [
              ImgBtn(asset: 'assets/btn_store.png', height: 58, onTap: () async {
                await Navigator.of(context).push(MaterialPageRoute(builder: (_) => StoreScreen(save: save)));
                setState(() {});
              }),
              const SizedBox(width: 14),
              ImgBtn(asset: 'assets/btn_achievements.png', height: 58, onTap: () {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => AwardsScreen(save: save)));
              }),
              const SizedBox(width: 14),
              ImgBtn(asset: 'assets/btn_settings.png', height: 58, onTap: () async {
                await Navigator.of(context).push(MaterialPageRoute(builder: (_) => SettingsScreen(save: save)));
                setState(() {});
              }),
            ]),
          ]),
        ),
        // hero on the left
        Align(alignment: const Alignment(-0.62, 0.62), child: _charOnStage()),
        // chest bottom right
        Positioned(right: 22, bottom: 70, child: _chest()),
        // coins top right
        Positioned(top: 14, right: 16, child: _coinPill()),
      ]),
    );
  }
}

// ---------- Shared small UI ----------
Widget lpPanel({required Widget child, EdgeInsets padding = const EdgeInsets.all(18)}) {
  return Container(
    padding: padding,
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0xFFFFC93C), width: 3),
      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))],
    ),
    child: child,
  );
}

Widget lpScreenBg({required Widget child}) {
  return Stack(fit: StackFit.expand, children: [
    Image.asset('assets/sky.jpg', fit: BoxFit.cover),
    Align(alignment: Alignment.bottomCenter, child: Image.asset('assets/hills.png', fit: BoxFit.fitWidth, alignment: Alignment.bottomCenter)),
    SafeArea(child: child),
  ]);
}

Widget lpTitle(String text) {
  return Text(text, style: const TextStyle(
    fontSize: 30, fontWeight: FontWeight.w900, color: Colors.white,
    shadows: [Shadow(color: Colors.black45, blurRadius: 4, offset: Offset(0, 2))],
  ));
}

Widget backBtn(BuildContext context) {
  return GestureDetector(
    onTap: () {
      Sfx.play('click');
      Navigator.of(context).pop();
    },
    child: Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white54, width: 2),
      ),
      child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 26),
    ),
  );
}

// ---------- Level select ----------
class LevelSelectScreen extends StatelessWidget {
  final SaveData save;
  const LevelSelectScreen({super.key, required this.save});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: lpScreenBg(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: Row(children: [
              backBtn(context),
              const SizedBox(width: 14),
              lpTitle('WORLD 1'),
              const Spacer(),
              Row(children: [
                Image.asset('assets/coin_0.png', height: 24),
                const SizedBox(width: 6),
                Text('${save.coins}', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
              ]),
            ]),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(children: [
                  for (var i = 0; i < kLevels.length; i++) ...[
                    _levelCard(context, i),
                    const SizedBox(width: 18),
                  ],
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _levelCard(BuildContext context, int i) {
    final unlocked = i < save.unlockedLevel;
    final hasStar = save.stars[i] == 1;
    final def = kLevels[i];
    return GestureDetector(
      onTap: () {
        if (!unlocked) return;
        Sfx.play('click');
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => GameScreen(save: save, levelIndex: i),
        ));
      },
      child: lpPanel(
        child: SizedBox(
          width: 190,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: unlocked ? const Color(0xFF66BB6A) : Colors.grey,
                border: Border.all(color: Colors.white, width: 4),
              ),
              child: Center(
                child: unlocked
                    ? Text('${i + 1}', style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: Colors.white))
                    : const Icon(Icons.lock_rounded, color: Colors.white, size: 30),
              ),
            ),
            const SizedBox(height: 10),
            Text(def.name, textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF4E342E))),
            const SizedBox(height: 6),
            Icon(hasStar ? Icons.star_rounded : Icons.star_border_rounded,
                color: hasStar ? const Color(0xFFFFC93C) : Colors.black26, size: 34),
          ]),
        ),
      ),
    );
  }
}

// ---------- Store ----------
class StoreScreen extends StatefulWidget {
  final SaveData save;
  const StoreScreen({super.key, required this.save});
  @override
  State<StoreScreen> createState() => _StoreState();
}

class _StoreState extends State<StoreScreen> {
  SaveData get save => widget.save;

  Future<void> _tapChar(CharDef c) async {
    if (save.owned.contains(c.id)) {
      save.character = c.id;
      await save.save();
      Sfx.play('click');
      if (mounted) setState(() {});
      return;
    }
    if (save.coins >= c.price) {
      save.coins -= c.price;
      save.owned.add(c.id);
      save.character = c.id;
      if (save.owned.length == kRoster.length) save.awards.add('roster');
      await save.save();
      Sfx.play('powerup');
      if (!mounted) return;
      setState(() {});
      if (true) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${c.name} unlocked! ${c.ability}'),
          duration: const Duration(seconds: 2),
        ));
      }
    } else {
      Sfx.play('hurt', volume: 0.5);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Need ${c.price - save.coins} more coins for ${c.name}.'),
          duration: const Duration(seconds: 2),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: lpScreenBg(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: Row(children: [
              backBtn(context),
              const SizedBox(width: 14),
              lpTitle('STORE'),
              const Spacer(),
              Row(children: [
                Image.asset('assets/coin_0.png', height: 24),
                const SizedBox(width: 6),
                Text('${save.coins}', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
              ]),
            ]),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
              child: Wrap(
                spacing: 14,
                runSpacing: 14,
                alignment: WrapAlignment.center,
                children: [for (final c in kRoster) _charCard(c)],
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _charCard(CharDef c) {
    final owned = save.owned.contains(c.id);
    final selected = save.character == c.id;
    final img = c.id == 'kai' ? 'assets/idle_0.png' : 'assets/${c.id}.png';
    return GestureDetector(
      onTap: () => _tapChar(c),
      child: Container(
        width: 168,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFFF9C4) : Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? const Color(0xFFFFB300) : Colors.white,
            width: selected ? 4 : 2,
          ),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 3))],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Image.asset(img, height: 96, fit: BoxFit.contain),
          const SizedBox(height: 6),
          Text(c.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF4E342E))),
          Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: const Color(0xFF66BB6A), borderRadius: BorderRadius.circular(10)),
            child: Text(c.ability, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
          ),
          Text(c.desc, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10.5, color: Colors.black54)),
          const SizedBox(height: 6),
          if (selected)
            const Text('SELECTED', style: TextStyle(color: Color(0xFFFF8F00), fontWeight: FontWeight.w900, fontSize: 13))
          else if (owned)
            const Text('TAP TO SELECT', style: TextStyle(color: Color(0xFF43A047), fontWeight: FontWeight.w800, fontSize: 12))
          else
                      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Image.asset('assets/coin_0.png', height: 18),
              const SizedBox(width: 4),
              Text('${c.price}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Color(0xFF6D4C41))),
            ]),
        ]),
      ),
    );
  }
}

// ---------- Awards ----------
class AwardDef {
  final String id;
  final String name;
  final String desc;
  const AwardDef(this.id, this.name, this.desc);
}

const List<AwardDef> kAwards = [
  AwardDef('first_win', 'First Steps', 'Finish your first level.'),
  AwardDef('world1', 'World 1 Hero', 'Finish all 4 levels of World 1.'),
  AwardDef('star1', 'Star Hunter', 'Collect a hidden star.'),
  AwardDef('rich', 'Coin Stacker', 'Hold 1000 coins at once.'),
  AwardDef('roster', 'Full Team', 'Unlock every character.'),
];

class AwardsScreen extends StatelessWidget {
  final SaveData save;
  const AwardsScreen({super.key, required this.save});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: lpScreenBg(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: Row(children: [backBtn(context), const SizedBox(width: 14), lpTitle('AWARDS')]),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
              itemCount: kAwards.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final a = kAwards[i];
                final got = save.awards.contains(a.id);
                return lpPanel(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(children: [
                    Icon(got ? Icons.emoji_events_rounded : Icons.lock_outline_rounded,
                        size: 40, color: got ? const Color(0xFFFFB300) : Colors.black26),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(a.name, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900,
                            color: got ? const Color(0xFF4E342E) : Colors.black38)),
                        Text(a.desc, style: TextStyle(fontSize: 12.5, color: got ? Colors.black54 : Colors.black38)),
                      ]),
                    ),
                    if (got) const Icon(Icons.check_circle_rounded, color: Color(0xFF43A047)),
                  ]),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}

// ---------- Settings ----------
class SettingsScreen extends StatefulWidget {
  final SaveData save;
  const SettingsScreen({super.key, required this.save});
  @override
  State<SettingsScreen> createState() => _SettingsState();
}

class _SettingsState extends State<SettingsScreen> {
  SaveData get save => widget.save;

  Future<void> _reset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset progress?'),
        content: const Text('Coins, levels, stars and characters will be lost.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('RESET')),
        ],
      ),
    );
    if (ok == true) {
      save.coins = 0;
      save.unlockedLevel = 1;
      save.stars = [0, 0, 0, 0];
      save.awards = {};
      save.owned = {'kai'};
      save.character = 'kai';
      save.lastChest = '';
      await save.save();
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: lpScreenBg(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: Row(children: [backBtn(context), const SizedBox(width: 14), lpTitle('SETTINGS')]),
          ),
          const SizedBox(height: 14),
          Center(
            child: lpPanel(
              child: SizedBox(
                width: 380,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  SwitchListTile(
                    title: const Text('Sound', style: TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: const Text('Jump, coin and stomp effects'),
                    value: !Sfx.muted,
                    onChanged: (v) {
                      Sfx.muted = !v;
                      save.save();
                      Sfx.play('click');
                      setState(() {});
                    },
                  ),
                  SwitchListTile(
                    title: const Text('Notifications', style: TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: const Text('Daily reward and come-back reminders'),
                    value: save.notifications,
                    onChanged: (v) async {
                      save.notifications = v;
                      await save.save();
                      if (!v) {
                        await Notifier.cancelAll();
                      } else {
                        await Notifier.cancelComeback();
                      }
                      Sfx.play('click');
                      setState(() {});
                    },
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.delete_forever_rounded, color: Colors.redAccent),
                    title: const Text('Reset progress', style: TextStyle(fontWeight: FontWeight.w800, color: Colors.redAccent)),
                    onTap: _reset,
                  ),
                  const Divider(),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 6),
                    child: Text('LEAPARA v1.0 - made for Ahmed', style: TextStyle(color: Colors.black45, fontSize: 12)),
                  ),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

// ---------- Game ----------
enum _PlayState { playing, paused, dead, win }

class _Enemy {
  final String type;
  double x, y;
  double dir;
  final double x0;
  final double range;
  bool dying = false;
  double dieT = 0;
  double animT = 0;

  _Enemy(this.type, this.x, this.y, {this.dir = -1, this.range = 70}) : x0 = x;

  double get speed {
    switch (type) {
      case 'snail': return 26;
      case 'mushroom': return 46;
      case 'turtle': return 40;
      default: return 32; // slime
    }
  }

  double get w {
    switch (type) {
      case 'snail': return 46;
      case 'mushroom': return 42;
      case 'turtle': return 56;
      default: return 44;
    }
  }

  double get h {
    switch (type) {
      case 'snail': return 34;
      case 'mushroom': return 40;
      case 'turtle': return 38;
      default: return 34;
    }
  }

  int get frames => type == 'mushroom' ? 4 : 2;
}

class _FloatText {
  double x, y;
  final String text;
  final Color color;
  double t = 0;
  _FloatText(this.x, this.y, this.text, this.color);
}

class GameScreen extends StatefulWidget {
  final SaveData save;
  final int levelIndex;
  const GameScreen({super.key, required this.save, required this.levelIndex});
  @override
  State<GameScreen> createState() => _GameState();
}

class _GameState extends State<GameScreen> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const double dt = 1 / 120; // fixed physics step

  late final LevelDef level = kLevels[widget.levelIndex];
  late final HeroAbility ability = HeroAbility.of(widget.save.character);
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  double _accum = 0;

  _PlayState state = _PlayState.playing;

  // hero (feet position hx, hy)
  double hx = 80, hy = kGroundTop, vx = 0, vy = 0;
  static const double hw = 15, hh = 60; // hitbox half-width and height
  bool onGround = true;
  int faceDir = 1;
  double coyote = 0, jumpBuffer = 0;
  bool jumpHeld = false;
  double invulnT = 0;
  int hearts = 3;
  bool shieldUp = false; // Tuff
  double runAnimT = 0;
  double hurtT = 0;
  double spawnX = 80, spawnY = kGroundTop;
  int lastCheckpoint = -1;

  // input
  bool inLeft = false, inRight = false;

  // entities
  late List<_Enemy> enemies;
  late List<Offset?> coins;
  late List<bool> heartsTaken;
  late List<bool> gemsTaken;
  bool starTaken = false;
  final List<_FloatText> floats = [];
  int coinsGot = 0, gemsGot = 0;

  double camX = 0;
  double timeT = 0;

  SaveData get save => widget.save;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    shieldUp = ability.shield;
    enemies = [for (final e in level.enemies) _Enemy(e.type, e.x, e.y)];
    coins = List<Offset?>.from(level.coins);
    heartsTaken = List.filled(level.hearts.length, false);
    gemsTaken = List.filled(level.gems.length, false);
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState st) {
    if (st == AppLifecycleState.paused) {
      if (state == _PlayState.playing) setState(() => state = _PlayState.paused);
      if (save.notifications) Notifier.scheduleComeback();
    } else if (st == AppLifecycleState.resumed) {
      Notifier.cancelComeback();
    }
  }

  // ---------------- main loop ----------------
  void _onTick(Duration elapsed) {
    var frame = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (frame > 0.25) frame = 0.25; // avoid spiral after a stall
    if (state == _PlayState.playing) {
      _accum += frame;
      while (_accum >= dt) {
        _step(dt);
        _accum -= dt;
        if (state != _PlayState.playing) { _accum = 0; break; }
      }
    }
    timeT += frame;
    if (mounted) setState(() {});
  }

  double _approach(double v, double target, double rate) {
    if (v < target) return math.min(v + rate * dt, target);
    if (v > target) return math.max(v - rate * dt, target);
    return v;
  }

  late final List<Solid> _solids = [...level.grounds, ...level.crates];

  void _step(double dt) {
    // ---- timers
    if (coyote > 0) coyote -= dt;
    if (jumpBuffer > 0) jumpBuffer -= dt;
    if (invulnT > 0) invulnT -= dt;
    if (hurtT > 0) hurtT -= dt;

    // ---- horizontal intent
    final dir = (inRight ? 1 : 0) - (inLeft ? 1 : 0);
    if (dir != 0) faceDir = dir;
    final maxRun = 340.0 * ability.runMul;
    if (dir != 0) {
      vx = _approach(vx, dir * maxRun, (onGround ? 2600 : 1900));
    } else {
      vx = _approach(vx, 0, (onGround ? 3200 : 500));
    }

    // ---- jump
    if (jumpBuffer > 0 && (onGround || coyote > 0)) {
      vy = -920 * ability.jumpMul;
      onGround = false;
      coyote = 0;
      jumpBuffer = 0;
      Sfx.play('jump');
    }

    // ---- gravity (+ Skye glide)
    const grav = 2600.0;
    vy += grav * dt;
    double maxFall = 900;
    if (ability.glide && jumpHeld && !onGround && vy > 120) {
      vy = _approach(vy, 120, 2400);
      maxFall = 120;
    }
    if (vy > maxFall) vy = maxFall;

    // ---- move X and resolve
    hx += vx * dt;
    for (final s in _solids) {
      if (hx + hw > s.x && hx - hw < s.x + s.w && hy > s.y && hy - hh < s.y + s.h) {
        if (vx > 0) {
          hx = s.x - hw;
        } else if (vx < 0) {
          hx = s.x + s.w + hw;
        }
        vx = 0;
      }
    }
    if (hx < hw) hx = hw;
    if (hx > level.width - hw) hx = level.width - hw;

    // ---- move Y and resolve
    final prevFeet = hy;
    hy += vy * dt;
    final wasGround = onGround;
    onGround = false;
    for (final s in _solids) {
      if (hx + hw > s.x && hx - hw < s.x + s.w) {
        if (vy >= 0 && prevFeet <= s.y + 0.5 && hy >= s.y) {
          hy = s.y;
          _land();
        } else if (vy < 0 && prevFeet - hh >= s.y + s.h - 0.5 && hy - hh <= s.y + s.h) {
          hy = s.y + s.h + hh;
          vy = 0;
        }
      }
    }
    // one-way platforms
    if (vy >= 0) {
      for (final p in level.platforms) {
        if (hx + hw > p.x && hx - hw < p.x + p.w && prevFeet <= p.y + 1 && hy >= p.y) {
          hy = p.y;
          _land();
        }
      }
    }
    if (!onGround && wasGround && vy >= 0) coyote = 0.1;

    // fell into a pit
    if (hy > kH + 120) {
      _hurt(true);
    }

    // ---- run anim timer
    if (onGround && vx.abs() > 20) {
      runAnimT += dt * vx.abs() / maxRun;
    } else {
      runAnimT = 0;
    }

    // ---- enemies
    for (final e in enemies) {
      if (e.dying) {
        e.dieT += dt;
        continue;
      }
      e.animT += dt;
      e.x += e.dir * e.speed * dt;
      if (e.x < e.x0 - e.range) { e.x = e.x0 - e.range; e.dir = 1; }
      if (e.x > e.x0 + e.range) { e.x = e.x0 + e.range; e.dir = -1; }
      // overlap with hero
      if (invulnT <= 0 &&
          hx + hw > e.x - e.w / 2 && hx - hw < e.x + e.w / 2 &&
          hy > e.y - e.h && hy - hh < e.y) {
        if (vy > 60 && prevFeet <= e.y - e.h + 18) {
          // stomp!
          e.dying = true;
          e.dieT = 0;
          vy = -520;
          onGround = false;
          Sfx.play('stomp');
          _addFloat(e.x, e.y - e.h - 10, '+10', const Color(0xFF7B1FA2));
          coinsGot++; // small coin bonus for a stomp
        } else {
          _hurt(false, fromX: e.x);
        }
      }
    }
    enemies.removeWhere((e) => e.dying && e.dieT > 0.35);

    // ---- spikes hurt on touch
    if (invulnT <= 0) {
      for (final sp in level.spikes) {
        if (hx + hw - 4 > sp.x && hx - hw + 4 < sp.x + sp.w &&
            hy > sp.baseY - 22 && hy - hh < sp.baseY) {
          _hurt(false, fromX: sp.x + sp.w / 2);
          break;
        }
      }
    }

    // ---- collectibles
    final hcx = hx, hcy = hy - hh / 2;
    for (var i = 0; i < coins.length; i++) {
      final c = coins[i];
      if (c == null) continue;
      var pos = c;
      if (ability.magnet) {
        final d = (Offset(hcx, hcy) - pos).distance;
        if (d < 150 && d > 1) {
          final dirv = (Offset(hcx, hcy) - pos) / d;
          pos += dirv * 520 * dt;
          coins[i] = pos;
        }
      }
      if ((pos - Offset(hcx, hcy)).distance < 34) {
        coins[i] = null;
        coinsGot++;
        Sfx.play('coin', volume: 0.7);
        _addFloat(pos.dx, pos.dy - 16, '+1', const Color(0xFFFFB300));
      }
    }
    for (var i = 0; i < level.hearts.length; i++) {
      if (heartsTaken[i]) continue;
      if ((level.hearts[i] - Offset(hcx, hcy)).distance < 36) {
        heartsTaken[i] = true;
        if (hearts < 3) hearts++;
        Sfx.play('powerup');
        _addFloat(hcx, hcy - 40, '+HP', const Color(0xFFE53935));
      }
    }
    for (var i = 0; i < level.gems.length; i++) {
      if (gemsTaken[i]) continue;
      if ((level.gems[i] - Offset(hcx, hcy)).distance < 36) {
        gemsTaken[i] = true;
        gemsGot++;
        Sfx.play('gem');
        _addFloat(hcx, hcy - 40, '+25', const Color(0xFF00ACC1));
      }
    }
    if (!starTaken && (level.star - Offset(hcx, hcy)).distance < 42) {
      starTaken = true;
      Sfx.play('star');
      save.awards.add('star1');
      _addFloat(hcx, hcy - 46, 'STAR!', const Color(0xFFFFC93C));
    }

    // ---- checkpoints
    for (var i = 0; i < level.checkpoints.length; i++) {
      final cx = level.checkpoints[i];
      if (hx >= cx && lastCheckpoint < i) {
        lastCheckpoint = i;
        spawnX = cx;
        spawnY = kGroundTop;
        if (ability.shield) shieldUp = true; // Tuff recharges at checkpoints
        Sfx.play('checkpoint');
        _addFloat(cx, kGroundTop - 90, 'CHECKPOINT', const Color(0xFF43A047));
      }
    }

    // ---- flag / win
    if (hx >= level.flagX) {
      _win();
      return;
    }

    // ---- floats
    for (final f in floats) { f.t += dt; f.y -= 40 * dt; }
    floats.removeWhere((f) => f.t > 0.9);

    // ---- camera (exp smoothing, clamped)
    final lw = _logicalWidth;
    final target = (hx - lw * 0.42).clamp(0.0, math.max(0.0, level.width - lw));
    camX += (target - camX) * (1 - math.exp(-8 * dt));
  }

  double _logicalWidth = 960;

  void _land() {
    if (vy > 500) Sfx.play('land', volume: 0.5);
    vy = 0;
    onGround = true;
  }

  void _addFloat(double x, double y, String text, Color color) {
    floats.add(_FloatText(x, y, text, color));
  }

  void _hurt(bool pit, {double? fromX}) {
          if (state != _PlayState.playing) return;
    if (!pit && invulnT > 0) return;
    if (!pit && shieldUp) {
      shieldUp = false;
      invulnT = 1.0;
      Sfx.play('powerup');
      _addFloat(hx, hy - hh - 10, 'SHIELD!', const Color(0xFF1E88E5));
      return;
    }
    hearts--;
    Sfx.play('hurt');
    hurtT = 0.45;
    invulnT = 1.3;
    if (hearts <= 0) {
      state = _PlayState.dead;
      return;
    }
    if (pit) {
      hx = spawnX; hy = spawnY; vx = 0; vy = 0;
      camX = (spawnX - _logicalWidth * 0.42).clamp(0.0, math.max(0.0, level.width - _logicalWidth));
    } else {
      vy = -350;
      onGround = false;
      vx = (fromX != null && hx < fromX) ? -260 : 260;
    }
  }

  Future<void> _win() async {
    state = _PlayState.win;
    Sfx.play('win');
    final reward = coinsGot + gemsGot * 25 + (starTaken ? 50 : 0) + 30;
    save.coins += reward;
    if (starTaken) save.stars[widget.levelIndex] = 1;
    if (widget.levelIndex + 1 >= save.unlockedLevel && save.unlockedLevel < kLevels.length) {
      save.unlockedLevel = widget.levelIndex + 2;
    }
    save.awards.add('first_win');
    if (save.unlockedLevel >= kLevels.length) save.awards.add('world1');
    if (save.coins >= 1000) save.awards.add('rich');
    await save.save();
  }

  void _retry() {
    hx = spawnX; hy = spawnY; vx = 0; vy = 0;
    hearts = 3;
    invulnT = 1.0;
    hurtT = 0;
    shieldUp = ability.shield;
    camX = (spawnX - _logicalWidth * 0.42).clamp(0.0, math.max(0.0, level.width - _logicalWidth));
    state = _PlayState.playing;
  }

  void _pressJumpDown() {
    jumpHeld = true;
    jumpBuffer = 0.12;
  }

  void _pressJumpUp() {
    jumpHeld = false;
    if (vy < 0) vy *= 0.45; // variable jump height
  }

  // ---------------- UI ----------------
  Widget _ctlBtn({required Widget child, required VoidCallback onDown, required VoidCallback onUp, double size = 66}) {
    return Listener(
      onPointerDown: (_) => onDown(),
      onPointerUp: (_) => onUp(),
      onPointerCancel: (_) => onUp(),
      child: Container(
        width: size, height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.28),
          border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 2.5),
        ),
        child: Center(child: child),
      ),
    );
  }

  Widget _hud() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Row(children: [
          GestureDetector(
            onTap: () {
              Sfx.play('click');
              setState(() => state = _PlayState.paused);
            },
            child: Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.35),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white54, width: 2),
              ),
              child: const Icon(Icons.pause_rounded, color: Colors.white, size: 22),
            ),
          ),
          const SizedBox(width: 12),
          for (var i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsets.only(right: 3),
              child: Opacity(
                opacity: i < hearts ? 1 : 0.25,
                child: Image.asset('assets/heart.png', height: 26),
              ),
            ),
          if (ability.shield)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Icon(Icons.shield_rounded, size: 26,
                  color: shieldUp ? const Color(0xFF64B5F6) : Colors.white24),
            ),
          const Spacer(),
          Text(level.name.toUpperCase(), style: const TextStyle(
              color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900,
              shadows: [Shadow(color: Colors.black38, blurRadius: 3)])),
          const Spacer(),
          if (starTaken)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Icon(Icons.star_rounded, color: Color(0xFFFFC93C), size: 26),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white54, width: 2),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Image.asset('assets/coin_0.png', height: 20),
              const SizedBox(width: 6),
              Text('${save.coins + coinsGot + gemsGot * 25}', style: const TextStyle(
                  color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _overlay({required String title, required List<Widget> children, Color titleColor = Colors.white}) {
    return Container(
      color: Colors.black.withValues(alpha: 0.55),
      child: Center(
        child: lpPanel(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(title, style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: titleColor == Colors.white ? const Color(0xFF4E342E) : titleColor)),
            const SizedBox(height: 12),
            ...children,
          ]),
        ),
      ),
    );
  }

  Widget _overlayBtn(String label, Color color, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          minimumSize: const Size(210, 46),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(23)),
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
        ),
        onPressed: () {
          Sfx.play('click');
          onTap();
        },
        child: Text(label),
      ),
    );
  }

  Widget _pauseOverlay() {
    return _overlay(title: 'PAUSED', children: [
      _overlayBtn('RESUME', const Color(0xFF43A047), () => setState(() => state = _PlayState.playing)),
      _overlayBtn('RESTART LEVEL', const Color(0xFFFB8C00), () {
        Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => GameScreen(save: save, levelIndex: widget.levelIndex),
        ));
      }),
      _overlayBtn(Sfx.muted ? 'SOUND: OFF' : 'SOUND: ON', const Color(0xFF1E88E5), () {
        Sfx.muted = !Sfx.muted;
        save.save();
        setState(() {});
      }),
      _overlayBtn('QUIT TO MENU', const Color(0xFF8E24AA), () => Navigator.of(context).pop()),
    ]);
  }

  Widget _deadOverlay() {
    return _overlay(title: 'OUCH!', children: [
      const Text('Out of hearts! Try again from the last checkpoint.', style: TextStyle(color: Colors.black54)),
      const SizedBox(height: 8),
      _overlayBtn('TRY AGAIN', const Color(0xFF43A047), () => setState(_retry)),
      _overlayBtn('QUIT TO MENU', const Color(0xFF8E24AA), () => Navigator.of(context).pop()),
    ]);
  }

  Widget _winOverlay() {
    final reward = coinsGot + gemsGot * 25 + (starTaken ? 50 : 0) + 30;
    final hasNext = widget.levelIndex + 1 < kLevels.length;
    return _overlay(title: 'LEVEL CLEAR!', children: [
      Row(mainAxisSize: MainAxisSize.min, children: [
        Image.asset('assets/coin_0.png', height: 26),
        const SizedBox(width: 6),
        Text('+$reward', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFFFF8F00))),
        const SizedBox(width: 16),
        Icon(starTaken ? Icons.star_rounded : Icons.star_border_rounded,
            size: 34, color: starTaken ? const Color(0xFFFFC93C) : Colors.black26),
      ]),
      const SizedBox(height: 6),
      Text('Coins $coinsGot  -  Gems $gemsGot/${level.gems.length}${starTaken ? "  -  STAR!" : ""}',
          style: const TextStyle(color: Colors.black54, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      if (hasNext)
        _overlayBtn('NEXT LEVEL', const Color(0xFF43A047), () {
          Navigator.of(context).pushReplacement(MaterialPageRoute(
            builder: (_) => GameScreen(save: save, levelIndex: widget.levelIndex + 1),
          ));
        })
      else
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: Text('WORLD 1 COMPLETE!', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF8E24AA))),
        ),
      _overlayBtn('REPLAY', const Color(0xFFFB8C00), () {
        Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => GameScreen(save: save, levelIndex: widget.levelIndex),
        ));
      }),
      _overlayBtn('MENU', const Color(0xFF8E24AA), () => Navigator.of(context).pop()),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(builder: (ctx, cons) {
        final scale = cons.maxHeight / kH;
        _logicalWidth = cons.maxWidth / scale;
        return Stack(fit: StackFit.expand, children: [
          CustomPaint(
            size: Size.infinite,
            painter: _GamePainter(game: this, scale: scale),
          ),
          _hud(),
          // controls
          Positioned(
            left: 18, bottom: 16,
            child: Row(children: [
              _ctlBtn(
                child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 34),
                onDown: () => inLeft = true,
                onUp: () => inLeft = false,
              ),
              const SizedBox(width: 14),
              _ctlBtn(
                child: const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 34),
                onDown: () => inRight = true,
                onUp: () => inRight = false,
              ),
            ]),
          ),
          Positioned(
            right: 20, bottom: 14,
            child: _ctlBtn(
              size: 88,
              child: const Text('JUMP', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
              onDown: _pressJumpDown,
              onUp: _pressJumpUp,
            ),
          ),
          if (state == _PlayState.paused) _pauseOverlay(),
          if (state == _PlayState.dead) _deadOverlay(),
          if (state == _PlayState.win) _winOverlay(),
        ]);
      }),
    );
  }
}

// ---------- Game painter: everything the player sees in the world ----------
class _GamePainter extends CustomPainter {
  final _GameState game;
  final double scale;
  _GamePainter({required this.game, required this.scale});

  static const Color pole = Color(0xFF8D6E63);

  void _img(Canvas c, String path, Rect dst, {double opacity = 1}) {
    final img = Art.imgs[path];
    if (img == null) return;
    final paint = Paint()
      ..filterQuality = FilterQuality.medium
      ..color = Colors.white.withValues(alpha: opacity);
    c.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()), dst, paint);
  }

  // tiled parallax layer that hugs the bottom of the screen
  void _parallax(Canvas c, Size logical, String path, double factor, double camX) {
    final img = Art.imgs[path];
    if (img == null) return;
    final h = logical.height;
    final w = h * img.width / img.height;
    var start = -(camX * factor) % w;
    if (start > 0) start -= w;
    for (var x = start; x < logical.width; x += w) {
      _img(c, path, Rect.fromLTWH(x, 0, w, h));
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final g = game;
    final logical = Size(size.width / scale, size.height / scale);
    canvas.scale(scale);

    // 1. sky
    _img(canvas, 'sky.jpg', Rect.fromLTWH(0, 0, logical.width, logical.height));

    // 2. drifting clouds (procedural)
    final cloudPaint = Paint()..color = Colors.white.withValues(alpha: 0.85);
    for (var i = 0; i < 4; i++) {
      final cw = 90.0 + i * 26;
      final cx = ((i * 340 + g.timeT * (8 + i * 3)) % (logical.width + 400)) - 200;
      final cy = 40.0 + i * 36;
      canvas.drawOval(Rect.fromCenter(center: Offset(cx, cy), width: cw, height: cw * 0.42), cloudPaint);
      canvas.drawOval(Rect.fromCenter(center: Offset(cx + cw * 0.28, cy - cw * 0.12), width: cw * 0.6, height: cw * 0.36), cloudPaint);
    }

    // 3. mountains + hills
    _parallax(canvas, logical, 'mountains.png', 0.22, g.camX);
    _parallax(canvas, logical, 'hills.png', 0.45, g.camX);

    // 4. world space
    canvas.save();
    canvas.translate(-g.camX, 0);
    final viewL = g.camX - 80;
    final viewR = g.camX + logical.width + 80;

    // grounds (tiled)
    for (final s in g.level.grounds) {
      if (s.x + s.w < viewL || s.x > viewR) continue;
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(s.x, s.y, s.w, s.h));
      for (var x = s.x; x < s.x + s.w; x += 64) {
        for (var y = s.y; y < s.y + s.h; y += 64) {
          _img(canvas, 'ground.png', Rect.fromLTWH(x, y, 64, 64));
        }
      }
      canvas.restore();
    }

    // props on the grass
    const propImgs = ['bush.png', 'flowers.png', 'grass.png'];
    for (final s in g.level.grounds) {
      if (s.y != kGroundTop) continue;
      for (var x = s.x + 190; x < s.x + s.w - 60; x += 260) {
        if (x < viewL || x > viewR) continue;
        final idx = (x ~/ 260) % propImgs.length;
        final ph = idx == 0 ? 44.0 : (idx == 1 ? 34.0 : 40.0);
        _img(canvas, propImgs[idx], Rect.fromLTWH(x, s.y - ph + 4, ph * 1.2, ph));
      }
    }

    // sign near spawn
    _img(canvas, 'sign.png', Rect.fromLTWH(18, kGroundTop - 52, 52, 52));

    // crates
    for (final s in g.level.crates) {
      if (s.x + s.w < viewL || s.x > viewR) continue;
      _img(canvas, 'crate.png', Rect.fromLTWH(s.x, s.y, s.w, s.h));
    }

    // one-way platforms
    for (final p in g.level.platforms) {
      if (p.x + p.w < viewL || p.x > viewR) continue;
      _img(canvas, 'platform.png', Rect.fromLTWH(p.x, p.y - 4, p.w, 38));
    }

    // spikes
    for (final sp in g.level.spikes) {
      if (sp.x + sp.w < viewL || sp.x > viewR) continue;
      _img(canvas, 'spikes.png', Rect.fromLTWH(sp.x, sp.baseY - 28, sp.w, 28));
    }

    // checkpoints
    for (var i = 0; i < g.level.checkpoints.length; i++) {
      final cx = g.level.checkpoints[i];
      if (cx < viewL || cx > viewR) continue;
      final active = g.lastCheckpoint >= i;
      final poleRect = Rect.fromLTWH(cx - 3, kGroundTop - 78, 6, 78);
      canvas.drawRRect(RRect.fromRectAndRadius(poleRect, const Radius.circular(3)), Paint()..color = pole);
      final flagColor = active ? const Color(0xFF43A047) : const Color(0xFFB0BEC5);
      final wave = math.sin(g.timeT * 6 + i) * 4;
      final path = Path()
        ..moveTo(cx + 3, kGroundTop - 78)
        ..lineTo(cx + 42, kGroundTop - 68 + wave)
        ..lineTo(cx + 3, kGroundTop - 56)
        ..close();
      canvas.drawPath(path, Paint()..color = flagColor);
      canvas.drawCircle(Offset(cx, kGroundTop - 80), 5, Paint()..color = flagColor);
    }

    // end flag
    final fx = g.level.flagX;
    if (fx > viewL && fx < viewR) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(fx - 4, kGroundTop - 120, 8, 120), const Radius.circular(4)),
        Paint()..color = pole,
      );
      final wave = math.sin(g.timeT * 5) * 6;
      final path = Path()
        ..moveTo(fx + 4, kGroundTop - 120)
        ..quadraticBezierTo(fx + 40, kGroundTop - 112 + wave, fx + 64, kGroundTop - 104 + wave)
        ..quadraticBezierTo(fx + 40, kGroundTop - 96, fx + 4, kGroundTop - 88)
        ..close();
      canvas.drawPath(path, Paint()..color = const Color(0xFFE53935));
      canvas.drawCircle(Offset(fx, kGroundTop - 124), 7, Paint()..color = const Color(0xFFFFC93C));
    }

    // collectibles
    for (var i = 0; i < g.coins.length; i++) {
      final cpos = g.coins[i];
      if (cpos == null || cpos.dx < viewL || cpos.dx > viewR) continue;
      final f = (g.timeT * 10 + i * 0.7).floor() % 6;
      final bob = math.sin(g.timeT * 3 + i) * 3;
      _img(canvas, 'coin_$f.png', Rect.fromCenter(center: Offset(cpos.dx, cpos.dy + bob), width: 34, height: 34));
    }
    for (var i = 0; i < g.level.hearts.length; i++) {
      if (g.heartsTaken[i]) continue;
      final p = g.level.hearts[i];
      if (p.dx < viewL || p.dx > viewR) continue;
      final bob = math.sin(g.timeT * 3 + i * 2) * 4;
      _img(canvas, 'heart.png', Rect.fromCenter(center: Offset(p.dx, p.dy + bob), width: 36, height: 36));
    }
    for (var i = 0; i < g.level.gems.length; i++) {
      if (g.gemsTaken[i]) continue;
      final p = g.level.gems[i];
      if (p.dx < viewL || p.dx > viewR) continue;
      final bob = math.sin(g.timeT * 2.5 + i * 1.3) * 4;
      _img(canvas, 'gem.png', Rect.fromCenter(center: Offset(p.dx, p.dy + bob), width: 38, height: 38));
    }
    if (!g.starTaken) {
      final p = g.level.star;
      final bob = math.sin(g.timeT * 2.5) * 5;
      final rot = math.sin(g.timeT * 2) * 0.15;
      canvas.save();
      canvas.translate(p.dx, p.dy + bob);
      canvas.rotate(rot);
      _img(canvas, 'star.png', Rect.fromCenter(center: Offset.zero, width: 50, height: 50));
      canvas.restore();
    }

    // enemies
    for (final e in g.enemies) {
      if (e.x < viewL || e.x > viewR) continue;
      final frame = (e.animT * 6).floor() % e.frames;
      final dw = e.w * 1.45;
      final dh = e.h * 1.45;
      final squash = e.dying ? math.max(0.05, 1 - e.dieT / 0.35) : 1.0;
      canvas.save();
      canvas.translate(e.x, e.y + 2);
      canvas.scale(e.dir > 0 ? -1.0 : 1.0, squash);
      _img(canvas, '${e.type}_$frame.png', Rect.fromLTWH(-dw / 2, -dh, dw, dh));
      canvas.restore();
    }

    // hero
    _drawHero(canvas, g);

    // floating texts
    for (final f in g.floats) {
      final tp = TextPainter(
        text: TextSpan(text: f.text, style: TextStyle(
          fontSize: 18, fontWeight: FontWeight.w900, color: f.color.withValues(alpha: (1 - f.t).clamp(0.0, 1.0)),
          shadows: const [Shadow(color: Colors.white, blurRadius: 3)],
        )),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(f.x - tp.width / 2, f.y));
    }

    canvas.restore();
  }

  void _drawHero(Canvas canvas, _GameState g) {
    final isKai = g.save.character == 'kai';
    double opacity = 1;
    if (g.invulnT > 0 && (g.timeT * 18).floor() % 2 == 0) opacity = 0.35;

    canvas.save();
    canvas.translate(g.hx, g.hy + 4);
    if (g.faceDir < 0) canvas.scale(-1, 1);

    if (isKai) {
      String path;
      if (g.hurtT > 0) {
        path = 'hurt_${(g.timeT * 8).floor() % 2}.png';
      } else if (!g.onGround) {
        if (g.vy < 0) {
          final idx = g.vy < -500 ? 0 : (g.vy < -200 ? 1 : 2);
          path = 'jump_$idx.png';
        } else {
          path = 'fall_${(g.timeT * 6).floor() % 2}.png';
        }
      } else if (g.vx.abs() > 20) {
        path = 'run_${(g.runAnimT * 10).floor() % 6}.png';
      } else {
        path = 'idle_${(g.timeT * 3).floor() % 4}.png';
      }
      _img(canvas, path, const Rect.fromLTWH(-50, -100, 100, 100), opacity: opacity);
    } else {
      // roster characters: single artwork + procedural squash / tilt / stretch
      final stretch = (1 + (g.vy / 3200).clamp(-0.10, 0.14));
      final tilt = g.onGround ? 0.05 * (g.vx / 340) : 0.12 * (g.vy / 900).clamp(-1.0, 1.0);
      canvas.rotate(tilt);
      canvas.scale(1 / math.sqrt(stretch), stretch);
      _img(canvas, '${g.save.character}.png', const Rect.fromLTWH(-48, -96, 96, 96), opacity: opacity);
    }
    canvas.restore();

    // Tuff shield bubble
    if (g.shieldUp) {
      canvas.drawCircle(
        Offset(g.hx, g.hy - 30),
        46 + math.sin(g.timeT * 4) * 2,
        Paint()
          ..color = const Color(0xFF64B5F6).withValues(alpha: 0.22)
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        Offset(g.hx, g.hy - 30),
        46 + math.sin(g.timeT * 4) * 2,
        Paint()
          ..color = const Color(0xFF64B5F6).withValues(alpha: 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GamePainter oldDelegate) => true;
}