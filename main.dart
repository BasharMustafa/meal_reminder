import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:shared_preferences/shared_preferences.dart';

const meals = <Meal>[
  Meal(0, 'الاستيقاظ', '05:00', '🌅', 'اشرب كوب ماء', 0, 0),
  Meal(1, 'الفطور', '05:30', '🍳', '3 بيض + خبز + حليب + موز', 851, 41.4),
  Meal(2, 'وجبة خفيفة', '08:30', '🥜', 'فول سوداني 40غ + 3 تمرات', 339, 11.4),
  Meal(3, 'الغداء', '12:00', '🍗', 'دجاج + أرز + زيت زيتون + سلطة', 905, 72.1),
  Meal(4, 'مشروب زيادة الوزن', '15:00', '🥤', 'حليب + شوفان + موز + زبدة فول سوداني + عسل', 858, 32.1),
  Meal(5, 'العشاء', '18:00', '🍝', 'معكرونة + جبنة + زيت زيتون + خضراوات', 739, 27.1),
  Meal(6, 'قبل النوم', '20:30', '🥛', 'حليب + موز', 260, 9),
];

class Meal {
  final int id;
  final String name, time, icon, description;
  final int kcal;
  final double protein;

  const Meal(
    this.id,
    this.name,
    this.time,
    this.icon,
    this.description,
    this.kcal,
    this.protein,
  );
}

final notifications = FlutterLocalNotificationsPlugin();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  tzdata.initializeTimeZones();

  try {
    final zone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(zone.identifier));
  } catch (_) {}

  const init = InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
  );

  await notifications.initialize(init);

  runApp(const MealApp());
}

class MealApp extends StatelessWidget {
  const MealApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'وجباتي',
    locale: const Locale('ar'),
    supportedLocales: const [Locale('ar')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xff1f5a3a),
      ),
      scaffoldBackgroundColor: const Color(0xfff1f4f2),
      fontFamily: 'Arial',
    ),
    home: const HomePage(),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int tab = 0;
  int lead = 0;

  bool sound = true;
  bool loading = true;

  DateTime start = DateTime.now();

  final Set<int> done = {};
  final Set<int> water = {};
  final List<Map<String, dynamic>> weights = [];

  final TextEditingController weightController =
      TextEditingController();

  static const storageKey = 'meal_reminder_flutter_v1';

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    weightController.dispose();
    super.dispose();
  }

  String dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(storageKey);

    if (raw != null) {
      try {
        final m = jsonDecode(raw);

        start = DateTime.parse(m['start']);
        lead = m['lead'] ?? 0;
        sound = m['sound'] ?? true;

        done.addAll(
          (m['done'] as List? ?? []).cast<int>(),
        );

        water.addAll(
          (m['water'] as List? ?? []).cast<int>(),
        );

        weights.addAll(
          (m['weights'] as List? ?? [])
              .cast<Map<String, dynamic>>(),
        );
      } catch (_) {}
    }

    setState(() => loading = false);
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();

    await p.setString(
      storageKey,
      jsonEncode({
        'start': dateKey(start),
        'lead': lead,
        'sound': sound,
        'done': done.toList(),
        'water': water.toList(),
        'weights': weights,
      }),
    );
  }

  Future<void> scheduleAll() async {
    await notifications.cancelAll();

    final android = notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    await android?.requestNotificationsPermission();

    final now = tz.TZDateTime.now(tz.local);

    final firstDay = DateTime(
      start.year,
      start.month,
      start.day,
    );

    for (final m in meals) {
      final parts = m.time.split(':');

      final h = int.parse(parts[0]);
      final min = int.parse(parts[1]);

      var at = tz.TZDateTime(
        tz.local,
        firstDay.year,
        firstDay.month,
        firstDay.day,
        h,
        min,
      );

      while (!at.isAfter(now)) {
        at = at.add(const Duration(days: 1));
      }

      final details = NotificationDetails(
        android: AndroidNotificationDetails(
          'meal_reminders',
          'تذكير الوجبات',
          channelDescription: 'مواعيد الوجبات اليومية',
          importance: Importance.max,
          priority: Priority.high,
          playSound: sound,
          enableVibration: true,
        ),
      );

      await notifications.zonedSchedule(
        m.id * 2 + 1,
        '${m.icon} ${m.name}',
        m.description,
        at,
        details,
        androidScheduleMode:
            AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );

      if (lead > 0) {
        var early = at.subtract(
          Duration(minutes: lead),
        );

        if (!early.isAfter(now)) {
          early = early.add(const Duration(days: 1));
        }

        await notifications.zonedSchedule(
          m.id * 2 + 2,
          'استعد للوجبة',
          'بعد $lead دقائق: ${m.name}',
          early,
          details,
          androidScheduleMode:
              AndroidScheduleMode.inexactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.time,
        );
      }
    }
  }

  int get totalKcal =>
      meals.fold(0, (s, m) => s + m.kcal);

  double get totalProtein =>
      meals.fold(0.0, (s, m) => s + m.protein);

  int get dayNumber =>
      DateTime.now()
          .difference(DateTime(start.year, start.month, start.day))
          .inDays +
      1;

  Future<void> chooseStart() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: start,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      locale: const Locale('ar'),
    );

    if (picked != null) {
      setState(() {
        start = DateTime(
          picked.year,
          picked.month,
          picked.day,
        );
      });

      await save();
      await scheduleAll();
    }
  }

  String fmt(DateTime d) =>
      '${d.day}/${d.month}/${d.year}';

  Widget mealCard(Meal m) {
    final checked = done.contains(m.id);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: CheckboxListTile(
        value: checked,
        onChanged: (v) {
          setState(() {
            v == true
                ? done.add(m.id)
                : done.remove(m.id);
          });

          save();
        },
        controlAffinity: ListTileControlAffinity.leading,
        title: Text(
          '${m.icon}  ${m.name}',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          '${m.time}  •  ${m.description}\n'
          '${m.kcal} سعرة  |  ${m.protein} غ بروتين',
        ),
        isThreeLine: true,
        activeColor: const Color(0xff1f5a3a),
      ),
    );
  }

  Widget todayView() => ListView(
    padding: const EdgeInsets.all(14),
    children: [
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [
              Color(0xff12295c),
              Color(0xff1f5a3a),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'خطة زيادة الوزن',
              style: TextStyle(color: Colors.white70),
            ),
            Text(
              'اليوم ${dayNumber.clamp(1, 90)} من 90',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 25,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'السعرات المخططة: $totalKcal'
              '  •  البروتين: ${totalProtein.toStringAsFixed(1)} غ',
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              'بداية البرنامج: ${fmt(start)}',
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),

      const SizedBox(height: 14),

      Row(
        children: [
          Expanded(
            child: statCard(
              'الوجبات المنجزة',
              '${done.length} / 6',
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: statCard(
              'الماء',
              '${water.length} / 12 كوب',
            ),
          ),
        ],
      ),

      const SizedBox(height: 12),

      const Text(
        'وجبات اليوم',
        style: TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.bold,
        ),
      ),

      ...meals.skip(1).map(mealCard),

      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '💧 متابعة شرب الماء',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                ),
              ),
              const Text(
                'كل كوب = 250 مل، الهدف 3 لترات يومياً',
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: List.generate(
                  12,
                  (i) => ChoiceChip(
                    label: Text('${i + 1}'),
                    selected: water.contains(i + 1),
                    onSelected: (v) {
                      setState(() {
                        v
                            ? water.add(i + 1)
                            : water.remove(i + 1);
                      });
                      save();
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );

  Widget statCard(String title, String value) =>
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Text(title),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      );

  Widget planView() => ListView(
    padding: const EdgeInsets.all(14),
    children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'إعدادات البرنامج',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),

              const SizedBox(height: 12),

              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('تاريخ بداية البرنامج'),
                subtitle: Text(fmt(start)),
                trailing: const Icon(Icons.calendar_month),
                onTap: chooseStart,
              ),

              const Divider(),

              const Text('التنبيه المسبق'),

              DropdownButton<int>(
                value: lead,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(
                    value: 0,
                    child: Text('بدون تنبيه مسبق'),
                  ),
                  DropdownMenuItem(
                    value: 5,
                    child: Text('قبل 5 دقائق'),
                  ),
                  DropdownMenuItem(
                    value: 10,
                    child: Text('قبل 10 دقائق'),
                  ),
                  DropdownMenuItem(
                    value: 15,
                    child: Text('قبل 15 دقيقة'),
                  ),
                ],
                onChanged: (v) async {
                  if (v != null) {
                    setState(() => lead = v);
                    await save();
                    await scheduleAll();
                  }
                },
              ),

              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('صوت واهتزاز التنبيه'),
                value: sound,
                onChanged: (v) async {
                  setState(() => sound = v);
                  await save();
                  await scheduleAll();
                },
              ),

              const SizedBox(height: 8),

              FilledButton.icon(
                onPressed: () async {
                  await scheduleAll();

                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'تم تفعيل وجدولة تذكيرات الوجبات',
                        ),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.notifications_active),
                label: const Text('تفعيل التنبيهات'),
              ),
            ],
          ),
        ),
      ),

      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'الأهداف اليومية',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              const ListTile(
                title: Text('السعرات الحرارية'),
                trailing: Text('3200 – 3600'),
              ),
              const ListTile(
                title: Text('البروتين'),
                trailing: Text('150 – 160 غ'),
              ),
              const ListTile(
                title: Text('الدهون'),
                trailing: Text('90 – 100 غ'),
              ),
              const ListTile(
                title: Text('الكربوهيدرات'),
                trailing: Text('400 – 480 غ'),
              ),
            ],
          ),
        ),
      ),

      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'تسجيل الوزن',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),

              TextField(
                controller: weightController,
                keyboardType:
                    const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'الوزن بالكيلوغرام',
                  hintText: 'مثال: 62.5',
                ),
              ),

              const SizedBox(height: 8),

              FilledButton(
                onPressed: () async {
                  final v = double.tryParse(
                    weightController.text.replaceAll(',', '.'),
                  );

                  if (v == null || v < 30 || v > 200) {
                    return;
                  }

                  setState(() {
                    weights.add({
                      'date': dateKey(DateTime.now()),
                      'kg': v,
                    });
                  });

                  weightController.clear();
                  await save();
                },
                child: const Text('حفظ الوزن'),
              ),

              ...weights.reversed.take(10).map(
                (w) => ListTile(
                  dense: true,
                  title: Text('${w['kg']} كغ'),
                  subtitle: Text(w['date'].toString()),
                ),
              ),
            ],
          ),
        ),
      ),

      const Padding(
        padding: EdgeInsets.all(12),
        child: Text(
          'ملاحظة: تسمح إعدادات الهاتف للتطبيق بإرسال الإشعارات. '
          'قد يؤخر نظام توفير البطارية بعض التنبيهات.',
          textAlign: TextAlign.center,
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final pages = [
      todayView(),
      planView(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('وجباتي 🍽️'),
        centerTitle: true,
      ),
      body: pages[tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (v) {
          setState(() => tab = v);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.restaurant),
            label: 'اليوم',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings),
            label: 'الخطة والإعدادات',
          ),
        ],
      ),
    );
  }
}
