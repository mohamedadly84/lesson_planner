import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'package:intl/intl.dart';

final dateF = DateFormat('yyyy-MM-dd');
final timeF = DateFormat('HH:mm');

// ==================== MODELS ====================
class Child {
  int? id;
  String name;
  String grade;
  Child({this.id, required this.name, required this.grade});
  Map<String, dynamic> toMap() => {'id': id, 'name': name, 'grade': grade};
  factory Child.fromMap(Map m) => Child(id: m['id'], name: m['name'], grade: m['grade']);
}

class Lesson {
  int? id;
  int childId;
  String title;
  String type; // private | school
  DateTime dateTime;
  String location;
  String notes;
  bool reminders;
  Lesson({this.id, required this.childId, required this.title, required this.type, required this.dateTime, this.location = '', this.notes = '', this.reminders = true});
  Map<String, dynamic> toMap() => {
    'id': id, 'child_id': childId, 'title': title, 'type': type,
    'datetime': dateF.format(dateTime) + ' ' + timeF.format(dateTime),
    'location': location, 'notes': notes, 'reminders': reminders ? 1 : 0};
  factory Lesson.fromMap(Map m) => Lesson(
    id: m['id'], childId: m['child_id'], title: m['title'], type: m['type'],
    dateTime: DateTime.parse(m['datetime']), location: m['location'] ?? '',
    notes: m['notes'] ?? '', reminders: m['reminders'] == 1);
}

class SchoolPeriod {
  int? id;
  int childId;
  int dayOfWeek; // 1=Mon ... 7=Sun
  int periodNo;
  String subject;
  String teacher;
  String room;
  String startTime;
  String endTime;
  SchoolPeriod({this.id, required this.childId, required this.dayOfWeek, required this.periodNo, required this.subject, this.teacher = '', this.room = '', this.startTime = '', this.endTime = ''});
  Map<String, dynamic> toMap() => {'id': id, 'child_id': childId, 'day_of_week': dayOfWeek, 'period_no': periodNo, 'subject': subject, 'teacher': teacher, 'room': room, 'start_time': startTime, 'end_time': endTime};
  factory SchoolPeriod.fromMap(Map m) => SchoolPeriod(id: m['id'], childId: m['child_id'], dayOfWeek: m['day_of_week'], periodNo: m['period_no'], subject: m['subject'], teacher: m['teacher'] ?? '', room: m['room'] ?? '', startTime: m['start_time'] ?? '', endTime: m['end_time'] ?? '');
}

class SchoolHoliday {
  int? id;
  int? childId; // null = applies to all
  String date;
  String reason;
  String type; // official | sick | custom
  SchoolHoliday({this.id, this.childId, required this.date, required this.reason, this.type = 'custom'});
  Map<String, dynamic> toMap() => {'id': id, 'child_id': childId, 'date': date, 'reason': reason, 'type': type};
  factory SchoolHoliday.fromMap(Map m) => SchoolHoliday(id: m['id'], childId: m['child_id'], date: m['date'], reason: m['reason'], type: m['type'] ?? 'custom');
}

// ==================== DATABASE ====================
class DatabaseHelper {
  static Database? _db;
  Future<Database> get db async => _db ??= await _init();

  Future<Database> _init() async {
    final dir = await getApplicationDocumentsDirectory();
    return openDatabase(join(dir.path, 'lesson_planner.db'), version: 1,
        onCreate: (db, version) async {
      await db.execute('''CREATE TABLE children(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, grade TEXT)''');
      await db.execute('''CREATE TABLE lessons(id INTEGER PRIMARY KEY AUTOINCREMENT, child_id INTEGER, title TEXT, type TEXT, datetime TEXT, location TEXT, notes TEXT, reminders INTEGER)''');
      await db.execute('''CREATE TABLE school_periods(id INTEGER PRIMARY KEY AUTOINCREMENT, child_id INTEGER, day_of_week INTEGER, period_no INTEGER, subject TEXT, teacher TEXT, room TEXT, start_time TEXT, end_time TEXT)''');
      await db.execute('''CREATE TABLE school_holidays(id INTEGER PRIMARY KEY AUTOINCREMENT, child_id INTEGER, date TEXT, reason TEXT, type TEXT)''');
    });
  }

  // Children
  Future<int> insertChild(Child c) => (await db).insert('children', c.toMap());
  Future<List<Child>> getChildren() async {
    final list = await (await db).query('children');
    return list.map((e) => Child.fromMap(e)).toList();
  }
  Future<int> deleteChild(int id) => (await db).delete('children', where: 'id = ?', whereArgs: [id]);

  // Lessons
  Future<int> insertLesson(Lesson l) => (await db).insert('lessons', l.toMap());
  Future<List<Lesson>> getLessons(int childId) async {
    final list = await (await db).query('lessons', where: 'child_id = ?', whereArgs: [childId], orderBy: 'datetime');
    return list.map((e) => Lesson.fromMap(e)).toList();
  }
  Future<int> deleteLesson(int id) => (await db).delete('lessons', where: 'id = ?', whereArgs: [id]);

  // Periods
  Future<int> insertPeriod(SchoolPeriod p) => (await db).insert('school_periods', p.toMap());
  Future<List<SchoolPeriod>> getPeriods(int childId, int dayOfWeek) async {
    final list = await (await db).query('school_periods', where: 'child_id = ? AND day_of_week = ?', whereArgs: [childId, dayOfWeek], orderBy: 'period_no');
    return list.map((e) => SchoolPeriod.fromMap(e)).toList();
  }
  Future<List<SchoolPeriod>> getPeriodsForDate(int childId, String date) async {
    // daily override not implemented in MVP schema; falls back to weekly dayOfWeek
    final d = DateTime.parse(date);
    final dow = d.weekday; // 1=Mon ... 7=Sun
    return getPeriods(childId, dow);
  }
  Future<int> deletePeriod(int id) => (await db).delete('school_periods', where: 'id = ?', whereArgs: [id]);

  // Holidays
  Future<int> insertHoliday(SchoolHoliday h) => (await db).insert('school_holidays', h.toMap());
  Future<List<SchoolHoliday>> getHolidays() async {
    final list = await (await db).query('school_holidays', orderBy: 'date');
    return list.map((e) => SchoolHoliday.fromMap(e)).toList();
  }
  Future<bool> isHoliday(int childId, String date) async {
    final list = await (await db).query('school_holidays', where: 'date = ? AND (child_id IS NULL OR child_id = ?)', whereArgs: [date, childId]);
    return list.isNotEmpty;
  }
  Future<int> deleteHoliday(int id) => (await db).delete('school_holidays', where: 'id = ?', whereArgs: [id]);
}

// ==================== NOTIFICATIONS ====================
class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    tz.initializeTimeZones();
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _notifications.initialize(settings);
    await _notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
    await _notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestExactAlarmsPermission();
  }

  static Future<void> schedule(int id, String title, String body, DateTime scheduled, {String? payload}) async {
    final tzDate = tz.TZDateTime.from(scheduled, tz.local);
    await _notifications.zonedSchedule(
      id, title, body, tzDate,
      const NotificationDetails(android: AndroidNotificationDetails('channel_id', 'قناة التذكيرات', channelDescription: 'تذكيرات الدروس والحصص', importance: Importance.high, priority: Priority.high)),
      androidAllowWhileIdle: true,
      matchDateTimeComponents: tz.DateTimeComponents.dateAndTime,
      payload: payload,
    );
  }

  static Future<void> cancel(int id) => _notifications.cancel(id);

  // Lesson reminders: day before + hour before
  static Future<void> scheduleLessonReminders(int lessonId, String title, String childName, DateTime lessonDateTime) async {
    final dayBefore = lessonDateTime.subtract(const Duration(days: 1));
    final hourBefore = lessonDateTime.subtract(const Duration(hours: 1));
    final now = DateTime.now();
    if (dayBefore.isAfter(now)) {
      await schedule(lessonId * 10, 'تذكير درس', '$title - $childName', dayBefore, payload: 'lesson_$lessonId');
    }
    if (hourBefore.isAfter(now)) {
      await schedule(lessonId * 10 + 1, 'تنبيه قبل ساعة', '$title يبدأ خلال ساعة - $childName', hourBefore, payload: 'lesson_$lessonId');
    }
  }

  // Bag prep reminder: 18:00 yesterday
  static Future<void> scheduleBagPrep(int childId, String childName, DateTime targetDate, List<String> subjects) async {
    final prepTime = DateTime(targetDate.year, targetDate.month, targetDate.day, 18, 0);
    final isHoliday = false; // checked by caller
    await schedule(childId * 100 + targetDate.day, 'جهز الشنطة لغد', 'مواد $childName غداً: ${subjects.join('، ')}', prepTime, payload: 'bag_$childId');
  }
}

// ==================== APP ====================
class LessonPlannerApp extends StatelessWidget {
  const LessonPlannerApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'منظم الدروس',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: const Color(0xFF0F0F13)),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الصفحة الرئيسية')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('أهلاً بك في منظم الدروس والحصص', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            ElevatedButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ChildrenScreen())), icon: const Icon(Icons.person_add), label: const Text('إدارة الأطفال')),
            const SizedBox(height: 12),
            ElevatedButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TimetableScreen())), icon: const Icon(Icons.schedule), label: const Text('جدول الحصص')),
            const SizedBox(height: 12),
            ElevatedButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HolidaysScreen())), icon: const Icon(Icons.event), label: const Text('أيام الإجازة')),
            const SizedBox(height: 12),
            ElevatedButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BagPrepScreen())), icon: const Icon(Icons.inventory_2), label: const Text('تحضير الشنطة')),
          ],
        ),
      ),
    );
  }
}

// ==================== CHILDREN ====================
class ChildrenScreen extends StatefulWidget {
  const ChildrenScreen({super.key});
  @override
  State<ChildrenScreen> createState() => _ChildrenScreenState();
}

class _ChildrenScreenState extends State<ChildrenScreen> {
  final db = DatabaseHelper();
  final nameC = TextEditingController();
  final gradeC = TextEditingController();
  List<Child> children = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await db.getChildren();
    setState(() => children = list);
  }

  Future<void> _add() async {
    if (nameC.text.isEmpty) return;
    await db.insertChild(Child(name: nameC.text, grade: gradeC.text));
    nameC.clear(); gradeC.clear();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الأطفال')),
      body: Column(
        children: [
          Padding(
            padding: const Padding.all(12),
            child: Row(
              children: [
                Expanded(child: TextField(controller: nameC, decoration: const InputDecoration(labelText: 'اسم الطفل'))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: gradeC, decoration: const InputDecoration(labelText: 'الصف'))),
                const SizedBox(width: 8),
                IconButton(onPressed: _add, icon: const Icon(Icons.add)),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: children.length,
              itemBuilder: (_, i) {
                final c = children[i];
                return ListTile(
                  title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(c.grade),
                  trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.redAccent), onPressed: () async {
                    await db.deleteChild(c.id!);
                    await _load();
                  }),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== LESSONS ====================
class AddLessonScreen extends StatefulWidget {
  final int childId;
  final String childName;
  const AddLessonScreen({super.key, required this.childId, required this.childName});
  @override
  State<AddLessonScreen> createState() => _AddLessonScreenState();
}

class _AddLessonScreenState extends State<AddLessonScreen> {
  final titleC = TextEditingController();
  final typeC = TextEditingController(text: 'private');
  final locC = TextEditingController();
  final notesC = TextEditingController();
  DateTime? selectedDateTime;
  final db = DatabaseHelper();

  Future<void> _pickDateTime() async {
    final d = await showDatePicker(context: context, firstDate: DateTime(2024), lastDate: DateTime(2030), initialDate: DateTime.now());
    if (d == null) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (t == null) return;
    setState(() => selectedDateTime = DateTime(d.year, d.month, d.day, t.hour, t.minute));
  }

  Future<void> _save() async {
    if (titleC.text.isEmpty || selectedDateTime == null) return;
    final l = Lesson(childId: widget.childId, title: titleC.text, type: typeC.text, dateTime: selectedDateTime!, location: locC.text, notes: notesC.text);
    final id = await db.insertLesson(l);
    if (l.reminders) {
      await NotificationService.scheduleLessonReminders(id, l.title, widget.childName, l.dateTime);
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('إضافة درس - ${widget.childName}')),
      body: Padding(
        padding: const Padding.all(16),
        child: Column(
          children: [
            TextField(controller: titleC, decoration: const InputDecoration(labelText: 'عنوان الدرس')),
            const SizedBox(height: 8),
            TextField(controller: typeC, decoration: const InputDecoration(labelText: 'النوع (مدرسة / خصوصي)')),
            const SizedBox(height: 8),
            TextField(controller: locC, decoration: const InputDecoration(labelText: 'المكان')),
            const SizedBox(height: 8),
            TextField(controller: notesC, decoration: const InputDecoration(labelText: 'ملاحظات')),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(selectedDateTime == null ? 'لم يتم اختيار موعد' : dateF.format(selectedDateTime!) + ' ' + timeF.format(selectedDateTime!)),
                const Spacer(),
                ElevatedButton.icon(onPressed: _pickDateTime, icon: const Icon(Icons.calendar_today), label: const Text('اختيار التاريخ والوقت')),
              ],
            ),
            const SizedBox(height: 12),
            CheckboxListTile(
              value: true,
              title: const Text('تفعيل التذكير (قبل يوم + قبل ساعة)'),
              onChanged: (v) {},
            ),
            const SizedBox(height: 12),
            SizedBox(width: double.infinity, height: 50, child: ElevatedButton(onPressed: _save, child: const Text('حفظ الدرس'))),
          ],
        ),
      ),
    );
  }
}

class LessonsScreen extends StatefulWidget {
  final int childId;
  final String childName;
  const LessonsScreen({super.key, required this.childId, required this.childName});
  @override
  State<LessonsScreen> createState() => _LessonsScreenState();
}

class _LessonsScreenState extends State<LessonsScreen> {
  final db = DatabaseHelper();
  List<Lesson> lessons = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await db.getLessons(widget.childId);
    setState(() => lessons = list);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('دروس ${widget.childName}')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AddLessonScreen(childId: widget.childId, childName: widget.childName))),
        child: const Icon(Icons.add),
      ),
      body: ListView.builder(
        itemCount: lessons.length,
        itemBuilder: (_, i) {
          final l = lessons[i];
          return ListTile(
            title: Text(l.title),
            subtitle: Text(dateF.format(l.dateTime) + ' ' + timeF.format(l.dateTime) + ' - ${l.type}'),
            trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.redAccent), onPressed: () async {
              await db.deleteLesson(l.id!);
              await _load();
            }),
          );
        },
      ),
    );
  }
}

// ==================== TIMETABLE ====================
class TimetableScreen extends StatefulWidget {
  const TimetableScreen({super.key});
  @override
  State<TimetableScreen> createState() => _TimetableScreenState>();
}

class _TimetableScreenState extends State<TimetableScreen> {
  final db = DatabaseHelper();
  List<Child> children = [];
  int? selectedChildId;
  String childName = '';
  int selectedDay = 1; // Monday
  List<SchoolPeriod> periods = [];

  final days = const {1: 'الاثنين', 2: 'الثلاثاء', 3: 'الأربعاء', 4: 'الخميس', 5: 'الجمعة', 6: 'السبت', 7: 'الأحد'};

  @override
  void initState() {
    super.initState();
    _loadChildren();
  }

  Future<void> _loadChildren() async {
    final list = await db.getChildren();
    setState(() => children = list);
    if (list.isNotEmpty) {
      setState(() => selectedChildId = list.first.id);
      childName = list.first.name;
      _loadPeriods();
    }
  }

  Future<void> _loadPeriods() async {
    if (selectedChildId == null) return;
    final list = await db.getPeriods(selectedChildId!, selectedDay);
    setState(() => periods = list);
  }

  Future<void> _addPeriod() async {
    if (selectedChildId == null) return;
    final subC = TextEditingController();
    final pNoC = TextEditingController(text: '1');
    final tC = TextEditingController();
    final rC = TextEditingController();
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('إضافة حصة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: subC, decoration: const InputDecoration(labelText: 'المادة')),
            TextField(controller: pNoC, decoration: const InputDecoration(labelText: 'رقم الحصة')),
            TextField(controller: tC, decoration: const InputDecoration(labelText: 'المدرس')),
            TextField(controller: rC, decoration: const InputDecoration(labelText: 'القاعة')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          ElevatedButton(onPressed: () async {
            await db.insertPeriod(SchoolPeriod(
              childId: selectedChildId!, dayOfWeek: selectedDay, periodNo: int.tryParse(pNoC.text) ?? 1,
              subject: subC.text, teacher: tC.text, room: rC.text));
            Navigator.pop(context);
            _loadPeriods();
          }, child: const Text('حفظ')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('جدول الحصص الأسبوعي')),
      body: Column(
        children: [
          Padding(
            padding: const Padding.all(12),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButton<int>(
                    value: selectedChildId,
                    hint: const Text('اختر طفلاً'),
                    items: children.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
                    onChanged: (v) {
                      setState(() {
                        selectedChildId = v;
                        childName = children.firstWhere((c) => c.id == v).name;
                        _loadPeriods();
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<int>(
                  value: selectedDay,
                  items: days.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                  onChanged: (v) {
                    setState(() {
                      selectedDay = v!;
                      _loadPeriods();
                    });
                  },
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(onPressed: _addPeriod, icon: const Icon(Icons.add), label: const Text('حصة')),
              ],
            ),
          ),
          Text('اليوم: ${days[selectedDay]} - $childName', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          Expanded(
            child: periods.isEmpty
                ? const Center(child: Text('لا توجد حصص لهذا اليوم'))
                : ListView.builder(
                    itemCount: periods.length,
                    itemBuilder: (_, i) {
                      final p = periods[i];
                      return ListTile(
                        title: Text(p.subject, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('الحصة ${p.periodNo} - ${p.startTime} إلى ${p.endTime}\n${p.teacher} - ${p.room}'),
                        trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.redAccent), onPressed: () async {
                          await db.deletePeriod(p.id!);
                          _loadPeriods();
                        }),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ==================== HOLIDAYS ====================
class HolidaysScreen extends StatefulWidget {
  const HolidaysScreen({super.key});
  @override
  State<HolidaysScreen> createState() => _HolidaysScreenState>();
}

class _HolidaysScreenState extends State<HolidaysScreen> {
  final db = DatabaseHelper();
  final reasonC = TextEditingController();
  DateTime? selectedDate;
  String type = 'custom';
  int? applyChildId;
  List<Child> children = [];
  List<SchoolHoliday> holidays = [];

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    final c = await db.getChildren();
    final h = await db.getHolidays();
    setState(() {
      children = c;
      holidays = h;
    });
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(context: context, firstDate: DateTime(2024), lastDate: DateTime(2030), initialDate: DateTime.now());
    if (d != null) setState(() => selectedDate = d);
  }

  Future<void> _save() async {
    if (reasonC.text.isEmpty || selectedDate == null) return;
    await db.insertHoliday(SchoolHoliday(
      childId: applyChildId,
      date: dateF.format(selectedDate!),
      reason: reasonC.text,
      type: type,
    ));
    reasonC.clear();
    await _loadAll();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('أيام الإجازة')),
      body: Column(
        children: [
          Padding(
            padding: const Padding.all(12),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: TextField(controller: reasonC, decoration: const InputDecoration(labelText: 'سبب الإجازة'))),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(onPressed: _pickDate, icon: const Icon(Icons.calendar_today), label: Text(selectedDate == null ? 'اختر التاريخ' : dateF.format(selectedDate!))),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('نوع الإجازة: '),
                    DropdownButton<String>(
                      value: type,
                      items: const [
                        DropdownMenuItem(value: 'official', child: Text('رسمية')),
                        DropdownMenuItem(value: 'sick', child: Text('مرض')),
                        DropdownMenuItem(value: 'custom', child: Text('مخصصة')),
                      ],
                      onChanged: (v) => setState(() => type = v!),
                    ),
                    const Spacer(),
                    DropdownButton<int?>(
                      value: applyChildId,
                      hint: const Text('الطفل (فارغ = الكل)'),
                      items: children.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
                      onChanged: (v) => setState(() => applyChildId = v),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(onPressed: _save, child: const Text('إضافة')),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: holidays.length,
              itemBuilder: (_, i) {
                final h = holidays[i];
                return ListTile(
                  title: Text(h.reason),
                  subtitle: Text('${h.date} - ${h.type} - ${h.childId == null ? 'جميع الأطفال' : 'طفل ID: ${h.childId}'}'),
                  trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.redAccent), onPressed: () async {
                    await db.deleteHoliday(h.id!);
                    await _loadAll();
                  }),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== BAG PREP ====================
class BagPrepScreen extends StatefulWidget {
  const BagPrepScreen({super.key});
  @override
  State<BagPrepScreen> createState() => _BagPrepScreenState>();
}

class _BagPrepScreenState extends State<BagPrepScreen> {
  final db = DatabaseHelper();
  List<Child> children = [];
  int? selectedChildId;

  @override
  void initState() {
    super.initState();
    _loadChildren();
  }

  Future<void> _loadChildren() async {
    final list = await db.getChildren();
    setState(() => children = list);
  }

  Future<void> _checkTomorrow() async {
    if (selectedChildId == null) return;
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final isH = await db.isHoliday(selectedChildId!, dateF.format(tomorrow));
    if (isH) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('غداً إجازة، لا حاجة لتحضير الشنطة')));
      return;
    }
    final periods = await db.getPeriodsForDate(selectedChildId!, dateF.format(tomorrow));
    final subjects = periods.map((p) => p.subject).toSet().toList();
    if (subjects.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا توجد حصص محددة لغداً')));
      return;
    }
    final childName = children.firstWhere((c) => c.id == selectedChildId).name;
    await NotificationService.scheduleBagPrep(selectedChildId!, childName, tomorrow, subjects);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم جدولة تذكير الشنطة لغد: ${subjects.join('، ')}')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تحضير الشنطة')),
      body: Column(
        children: [
          Padding(
            padding: const Padding.all(16),
            child: Column(
              children: [
                DropdownButton<int?>(
                  value: selectedChildId,
                  hint: const Text('اختر طفلاً'),
                  items: children.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
                  onChanged: (v) => setState(() => selectedChildId = v),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: _checkTomorrow,
                    icon: const Icon(Icons.check_circle),
                    label: const Text('تحقق من غداً وجدول التذكير'),
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          const Padding(
            padding: Padding.all(16),
            child: Text(
              'كيفية الاستخدام:\n'
              '1. أضف أطفالك من الصفحة الرئيسية.\n'
              '2. أضف حصص كل يوم من جدول الحصص.\n'
              '3. أضف أيام الإجازة من شاشة الإجازات.\n'
              '4. اضغط "تحقق من غداً" لتحديد مواد الشنطة وجدولة التذكير الساعة 6 مساءً.',
              style: TextStyle(color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}
