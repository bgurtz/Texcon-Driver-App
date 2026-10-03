import 'dart:async';
import 'package:flutter/material.dart';

void main() {
  runApp(const TexconDriverApp());
}

// ============================================================
// [SECTION 1: THEME & COLOR CONFIGURATION]
// ============================================================
class TexconColors {
  static const Color blue = Color(0xFF0057A8);
  static const Color darkBlue = Color(0xFF003B73);
  static const Color lightBlue = Color(0xFFEAF3FB);
  static const Color lightGreenCard = Color(0xFFE8F5E9);
  static const Color background = Color(0xFFF4F6F8);
  static const Color green = Color(0xFF16803C);
  static const Color red = Color(0xFFC62828);
  static const Color orange = Color(0xFFEF8A17);
  static const Color darkText = Color(0xFF17202A);
  static const Color grayText = Color(0xFF667085);
}

class TexconDriverApp extends StatelessWidget {
  const TexconDriverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Texcon Driver',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: TexconColors.blue,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: TexconColors.background,
        appBarTheme: const AppBarTheme(
          backgroundColor: TexconColors.blue,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      home: const MainDriverScreen(),
    );
  }
}

// ============================================================
// [SECTION 2: DATA MODELS]
// ============================================================
const Map<String, String> gCodes = {
  'G1193': 'Texcon Project',
  'G1200': 'Sample Job B',
  'G999': 'Yard',
};

const List<String> taskCodes = [
  'Pug – Yard Work / Sand',
  'Outside Sale',
  '300 – Storm Sewer',
  '400 – Sanitary Sewer',
  '500 – Water Line',
  '800 – Base',
  '900 – Asphalt',
];

const List<String> delayReasons = [
  'Waiting to Load',
  'Waiting to Unload',
  'Traffic Delay',
  'Railroad Train',
  'Accident',
  'Scale Backed Up',
  'Loader Breakdown',
  'Mechanical Issue',
  'Other',
];

enum LogEntryType { preTrip, postTrip, loadTrip, standaloneActivity }

class DailyLogEntry {
  final LogEntryType type;
  final DateTime startTime;
  DateTime? endTime;
  String equipmentInfo;
  String? startingMileage;
  String? endingMileage;
  String details;
  LoadTrip? loadTripData;
  TripActivity? standaloneActivity;

  DailyLogEntry({
    required this.type,
    required this.startTime,
    this.endTime,
    required this.equipmentInfo,
    this.startingMileage,
    this.endingMileage,
    this.details = '',
    this.loadTripData,
    this.standaloneActivity,
  });
}

class TripActivity {
  final String title;
  final DateTime startTime;
  DateTime? endTime;
  String notes;

  TripActivity({
    required this.title,
    required this.startTime,
    this.endTime,
    this.notes = '',
  });

  Duration get duration => (endTime ?? DateTime.now()).difference(startTime);
}

class LoadTrip {
  final int id;
  String gCode;
  String jobName;
  String taskCode;
  String material;
  String fromLocation;
  String toLocation;
  final DateTime startTime;
  DateTime? endTime;
  bool isCompleted;
  bool lunchTaken;
  Duration totalLunchDuration;
  final List<TripActivity> activities;

  LoadTrip({
    required this.id,
    required this.gCode,
    required this.jobName,
    required this.taskCode,
    required this.material,
    required this.fromLocation,
    required this.toLocation,
    required this.startTime,
    this.endTime,
    this.isCompleted = false,
    this.lunchTaken = false,
    this.totalLunchDuration = Duration.zero,
    List<TripActivity>? activities,
  }) : activities = activities ?? [TripActivity(title: 'Load Started', startTime: startTime, endTime: startTime)];

  Duration get duration => (endTime ?? DateTime.now()).difference(startTime);

  bool get isAsphaltTask => taskCode.toLowerCase().contains('asphalt');
}

// ============================================================
// [SECTION 3: UTILITIES]
// ============================================================
String formatTime(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  final s = d.second.toString().padLeft(2, '0');
  return '$h:$m:$s ${d.hour < 12 ? 'AM' : 'PM'}';
}

String formatDuration(Duration d) {
  final hours = d.inHours.toString().padLeft(2, '0');
  final minutes = (d.inMinutes % 60).toString().padLeft(2, '0');
  final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
  return '$hours:$minutes:$seconds';
}

String formatHoursWorked(Duration d) {
  final hours = d.inHours;
  final mins = d.inMinutes % 60;
  return '${hours}h ${mins}m';
}

// ============================================================
// [SECTION 4: MAIN DRIVER SCREEN STATE]
// ============================================================
class MainDriverScreen extends StatefulWidget {
  const MainDriverScreen({super.key});

  @override
  State<MainDriverScreen> createState() => _MainDriverScreenState();
}

class _MainDriverScreenState extends State<MainDriverScreen> {
  int currentTabIndex = 0;
  bool isClockedIn = false;
  DateTime? clockInTime;

  // Pre-Trip / Post-Trip States
  bool isPreTripInProgress = false;
  bool isPreTripCompleted = false;
  DateTime? preTripStartTime;

  bool isPostTripInProgress = false;
  bool isPostTripCompleted = false;
  DateTime? postTripStartTime;

  String currentTruck = '245';
  String currentTrailer = '781';

  // Active Load & Timed Action States
  LoadTrip? activeLoad;
  TripActivity? activeTimedEvent; // Active Delay or Break
  bool isLunchInProgress = false;
  bool isLunchTakenToday = false;
  DateTime? lunchStartTime;
  Duration totalLunchDurationToday = Duration.zero;

  final List<DailyLogEntry> chronologicalLog = [];
  DateTime selectedDate = DateTime.now();
  Timer? timer;

  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  // --- CALCULATION LOGIC FOR DAILY TIME CARD ---
  bool get hasAsphaltLoadToday {
    if (activeLoad != null && activeLoad!.isAsphaltTask) return true;
    return chronologicalLog.any((entry) => entry.loadTripData != null && entry.loadTripData!.isAsphaltTask);
  }

  Duration get grossShiftDuration {
    if (clockInTime == null) return Duration.zero;
    return DateTime.now().difference(clockInTime!);
  }

  Duration get calculatedLunchDeduction {
    if (hasAsphaltLoadToday) {
      return Duration.zero;
    }
    if (isLunchTakenToday) {
      return totalLunchDurationToday < const Duration(minutes: 30)
          ? const Duration(minutes: 30)
          : totalLunchDurationToday;
    }
    return const Duration(minutes: 30);
  }

  Duration get netPaidShiftDuration {
    final gross = grossShiftDuration;
    final deduction = calculatedLunchDeduction;
    if (deduction >= gross) return Duration.zero;
    return gross - deduction;
  }

  // Helper Dialogs
  Future<String?> askText(String title, {String? initialValue, bool isNumber = false}) {
    final c = TextEditingController(text: initialValue);
    return showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: isNumber ? TextInputType.number : TextInputType.text,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, c.text.trim()), child: const Text('OK')),
        ],
      ),
    );
  }

  Future<String?> chooseOption(String title, List<String> options) {
    return showDialog<String>(
      context: context,
      builder: (d) => SimpleDialog(
        title: Text(title),
        children: [
          for (final o in options)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(d, o),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(o, style: const TextStyle(fontSize: 16)),
              ),
            )
        ],
      ),
    );
  }

  // Pre-Trip Logic
  Future<void> handlePreTripToggle() async {
    if (!isPreTripInProgress) {
      setState(() {
        isPreTripInProgress = true;
        preTripStartTime = DateTime.now();
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pre-Trip Inspection Started.')));
    } else {
      final miles = await askText('Enter Beginning Mileage', isNumber: true);
      if (!mounted) return;
      if (miles == null || miles.isEmpty) return;

      final now = DateTime.now();
      final preTripLog = DailyLogEntry(
        type: LogEntryType.preTrip,
        startTime: preTripStartTime ?? now,
        endTime: now,
        equipmentInfo: 'Truck #$currentTruck | Trailer #$currentTrailer',
        startingMileage: miles,
        details: 'Initial Pre-Trip Inspection',
      );

      setState(() {
        isPreTripInProgress = false;
        isPreTripCompleted = true;
        chronologicalLog.add(preTripLog);
      });

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pre-Trip Completed & Logged.')));
    }
  }

  // Post-Trip Logic
  Future<void> handlePostTripToggle() async {
    if (activeLoad != null || activeTimedEvent != null || isLunchInProgress) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please complete active loads, delays, or breaks before starting Post-Trip.')),
      );
      return;
    }

    if (!isPostTripInProgress) {
      setState(() {
        isPostTripInProgress = true;
        postTripStartTime = DateTime.now();
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Post-Trip Inspection Started.')));
    } else {
      final miles = await askText('Enter Ending Mileage', isNumber: true);
      if (!mounted) return;
      if (miles == null || miles.isEmpty) return;

      final now = DateTime.now();
      final postTripLog = DailyLogEntry(
        type: LogEntryType.postTrip,
        startTime: postTripStartTime ?? now,
        endTime: now,
        equipmentInfo: 'Truck #$currentTruck | Trailer #$currentTrailer',
        endingMileage: miles,
        details: 'End of Shift Post-Trip Inspection',
      );

      setState(() {
        isPostTripInProgress = false;
        isPostTripCompleted = true;
        isClockedIn = false;
        chronologicalLog.add(postTripLog);
      });

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Post-Trip Completed. Shift finished!')));
    }
  }

  // Start New Load
  Future<void> startNewLoad() async {
    if (activeTimedEvent != null || isLunchInProgress) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please end active Delay, Break, or Lunch before starting a load.')),
      );
      return;
    }

    final selectedG = await chooseOption('Select G-Code', [for (final k in gCodes.keys) '$k - ${gCodes[k]}']);
    if (!mounted) return;
    if (selectedG == null) return;
    final code = selectedG.split(' - ').first;

    final task = await chooseOption('Select Task Code', taskCodes);
    if (!mounted) return;
    if (task == null) return;

    final material = await askText('Material Name (e.g., Flex Base, Sand)');
    if (!mounted) return;
    if (material == null || material.isEmpty) return;

    final from = await chooseOption('Starting Location', ['Pugmill', 'Quarry', 'Yard', 'Other']);
    if (!mounted) return;
    if (from == null) return;

    String? to = gCodes[code];
    if (task == 'Outside Sale') {
      to = await chooseOption('Delivery Location', ['Yard', 'Plant', 'Customer Site', 'Other']);
      if (!mounted) return;
    }
    if (to == null) return;

    final now = DateTime.now();
    final loadCount = chronologicalLog.where((e) => e.type == LogEntryType.loadTrip).length + 1;
    final newTrip = LoadTrip(
      id: loadCount,
      gCode: code,
      jobName: gCodes[code]!,
      taskCode: task,
      material: material,
      fromLocation: from,
      toLocation: to,
      startTime: now,
    );

    final logEntry = DailyLogEntry(
      type: LogEntryType.loadTrip,
      startTime: now,
      equipmentInfo: 'Truck #$currentTruck | Trailer #$currentTrailer',
      loadTripData: newTrip,
    );

    setState(() {
      activeLoad = newTrip;
      chronologicalLog.add(logEntry);
    });
  }

  void completeActiveLoad() {
    if (activeLoad == null || activeTimedEvent != null || isLunchInProgress) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please end active Delay, Break, or Lunch before completing load.')),
      );
      return;
    }

    final now = DateTime.now();
    setState(() {
      activeLoad!.endTime = now;
      activeLoad!.isCompleted = true;
      activeLoad!.activities.add(TripActivity(title: 'Load Completed', startTime: now, endTime: now));
      activeLoad = null;
    });
  }

  // --- DELAY / BREAK CONTROL ---
  Future<void> startTimedEvent(String type) async {
    String note = '';
    if (type == 'Load Delay') {
      final reason = await chooseOption('Select Delay Reason', delayReasons);
      if (!mounted) return;
      if (reason == null) return;
      note = reason;

      final extra = await askText('Additional Details (Optional)');
      if (!mounted) return;
      if (extra != null && extra.isNotEmpty) {
        note = '$note - $extra';
      }
    } else if (type == 'Break') {
      final reason = await askText('Reason for Break (Optional)');
      if (!mounted) return;
      if (reason != null) note = reason;
    }

    final event = TripActivity(
      title: type,
      startTime: DateTime.now(),
      notes: note,
    );

    setState(() {
      activeTimedEvent = event;
      if (activeLoad != null) {
        activeLoad!.activities.add(event);
      } else {
        chronologicalLog.add(DailyLogEntry(
          type: LogEntryType.standaloneActivity,
          startTime: event.startTime,
          equipmentInfo: 'Truck #$currentTruck | Trailer #$currentTrailer',
          standaloneActivity: event,
        ));
      }
    });
  }

  void endTimedEvent() {
    if (activeTimedEvent == null) return;

    final now = DateTime.now();
    setState(() {
      activeTimedEvent!.endTime = now;
      activeTimedEvent = null;
    });
  }

  // --- LUNCH CONTROL ---
  void handleLunchToggle() {
    final now = DateTime.now();
    if (!isLunchInProgress) {
      final lunchActivity = TripActivity(
        title: 'Lunch Break',
        startTime: now,
      );

      setState(() {
        isLunchInProgress = true;
        lunchStartTime = now;
        if (activeLoad != null) {
          activeLoad!.lunchTaken = true;
          activeLoad!.activities.add(lunchActivity);
        } else {
          chronologicalLog.add(DailyLogEntry(
            type: LogEntryType.standaloneActivity,
            startTime: now,
            equipmentInfo: 'Truck #$currentTruck | Trailer #$currentTrailer',
            standaloneActivity: lunchActivity,
          ));
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lunch Break Started.')));
    } else {
      TripActivity? lunchActivity;
      if (activeLoad != null) {
        lunchActivity = activeLoad!.activities.firstWhere((a) => a.title == 'Lunch Break' && a.endTime == null);
      } else {
        final entry = chronologicalLog.firstWhere((e) => e.type == LogEntryType.standaloneActivity && e.standaloneActivity?.title == 'Lunch Break' && e.standaloneActivity?.endTime == null);
        lunchActivity = entry.standaloneActivity;
      }

      if (lunchActivity != null) {
        lunchActivity.endTime = now;
        final duration = lunchActivity.duration;

        setState(() {
          isLunchInProgress = false;
          isLunchTakenToday = true;
          totalLunchDurationToday += duration;
          if (activeLoad != null) {
            activeLoad!.totalLunchDuration += duration;
          }
        });
      }

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lunch Break Ended & Logged.')));
    }
  }

  // Edit single field on trip
  Future<void> editTripField(LoadTrip trip) async {
    final fieldToEdit = await chooseOption('Select Field to Edit', [
      'G-Code',
      'Task Code',
      'Material',
      'Pick-Up Location',
      'Delivery Location',
    ]);
    if (!mounted) return;
    if (fieldToEdit == null) return;

    switch (fieldToEdit) {
      case 'G-Code':
        final g = await chooseOption('Select New G-Code', [for (final k in gCodes.keys) '$k - ${gCodes[k]}']);
        if (!mounted) return;
        if (g != null) {
          final code = g.split(' - ').first;
          setState(() {
            trip.gCode = code;
            trip.jobName = gCodes[code]!;
          });
        }
        break;
      case 'Task Code':
        final task = await chooseOption('Select New Task Code', taskCodes);
        if (!mounted) return;
        if (task != null) setState(() => trip.taskCode = task);
        break;
      case 'Material':
        final mat = await askText('Enter Material Name', initialValue: trip.material);
        if (!mounted) return;
        if (mat != null && mat.isNotEmpty) setState(() => trip.material = mat);
        break;
      case 'Pick-Up Location':
        final loc = await chooseOption('Select Pick-Up Location', ['Pugmill', 'Quarry', 'Yard', 'Other']);
        if (!mounted) return;
        if (loc != null) setState(() => trip.fromLocation = loc);
        break;
      case 'Delivery Location':
        final loc = await chooseOption('Select Delivery Location', ['Yard', 'Plant', 'Customer Site', 'Other']);
        if (!mounted) return;
        if (loc != null) setState(() => trip.toLocation = loc);
        break;
    }
  }

  // ============================================================
  // [SECTION 5: VIEW BUILDERS]
  // ============================================================

  // TAB 1: MAIN ACTIVE DASHBOARD
  Widget buildActiveDashboard() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Status Bar
        Card(
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('SHIFT STATUS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: TexconColors.grayText)),
                    Text(
                      !isClockedIn
                          ? 'Clocked Out'
                          : (isPostTripInProgress
                              ? 'Post-Trip in Progress'
                              : (isPreTripInProgress
                                  ? 'Pre-Trip in Progress'
                                  : (isPreTripCompleted ? 'Pre-Trip Done' : 'Pre-Trip Pending'))),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: !isClockedIn ? TexconColors.red : (isPreTripCompleted ? TexconColors.green : TexconColors.orange),
                      ),
                    ),
                  ],
                ),
                Text('Truck #$currentTruck | Trailer #$currentTrailer', style: const TextStyle(fontWeight: FontWeight.bold, color: TexconColors.darkBlue)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        if (!isClockedIn)
          FilledButton.icon(
            onPressed: () => setState(() {
              isClockedIn = true;
              clockInTime = DateTime.now();
            }),
            style: FilledButton.styleFrom(backgroundColor: TexconColors.green, minimumSize: const Size.fromHeight(50)),
            icon: const Icon(Icons.play_arrow),
            label: const Text('CLOCK IN FOR SHIFT', style: TextStyle(fontWeight: FontWeight.bold)),
          )
        else if (!isPreTripCompleted)
          FilledButton.icon(
            onPressed: handlePreTripToggle,
            style: FilledButton.styleFrom(
              backgroundColor: isPreTripInProgress ? TexconColors.orange : TexconColors.blue,
              minimumSize: const Size.fromHeight(50),
            ),
            icon: Icon(isPreTripInProgress ? Icons.check_circle_outline : Icons.assignment_turned_in),
            label: Text(
              isPreTripInProgress ? 'END PRE-TRIP (Enter Mileage)' : 'START PRE-TRIP',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          )
        else ...[
          // ACTION CONTROLS (CLEAN 2x2 GRID FORMAT)
          const Text('Action Controls', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),

          Row(
            children: [
              // LOAD DELAY
              Expanded(
                child: activeTimedEvent?.title == 'Load Delay'
                    ? FilledButton.icon(
                        onPressed: endTimedEvent,
                        style: FilledButton.styleFrom(backgroundColor: TexconColors.red, padding: const EdgeInsets.symmetric(vertical: 12)),
                        icon: const Icon(Icons.stop_circle_outlined, size: 18),
                        label: Text('END DELAY (${formatDuration(activeTimedEvent!.duration)})', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      )
                    : OutlinedButton.icon(
                        onPressed: (activeTimedEvent != null || isLunchInProgress) ? null : () => startTimedEvent('Load Delay'),
                        icon: const Icon(Icons.warning_amber, color: TexconColors.orange, size: 18),
                        label: const Text('LOAD DELAY', style: TextStyle(fontSize: 12)),
                      ),
              ),
              const SizedBox(width: 8),

              // BREAK
              Expanded(
                child: activeTimedEvent?.title == 'Break'
                    ? FilledButton.icon(
                        onPressed: endTimedEvent,
                        style: FilledButton.styleFrom(backgroundColor: TexconColors.red, padding: const EdgeInsets.symmetric(vertical: 12)),
                        icon: const Icon(Icons.stop_circle_outlined, size: 18),
                        label: Text('END BREAK (${formatDuration(activeTimedEvent!.duration)})', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      )
                    : OutlinedButton.icon(
                        onPressed: (activeTimedEvent != null || isLunchInProgress) ? null : () => startTimedEvent('Break'),
                        icon: const Icon(Icons.free_breakfast, color: TexconColors.blue, size: 18),
                        label: const Text('BREAK', style: TextStyle(fontSize: 12)),
                      ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          Row(
            children: [
              // LUNCH BREAK (Compact Split Button)
              Expanded(
                child: isLunchInProgress
                    ? FilledButton.icon(
                        onPressed: handleLunchToggle,
                        style: FilledButton.styleFrom(backgroundColor: TexconColors.red, padding: const EdgeInsets.symmetric(vertical: 12)),
                        icon: const Icon(Icons.restaurant_menu, size: 18),
                        label: Text('END LUNCH (${formatDuration(DateTime.now().difference(lunchStartTime!))})', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      )
                    : OutlinedButton.icon(
                        onPressed: (activeTimedEvent != null || isLunchTakenToday) ? null : handleLunchToggle,
                        icon: const Icon(Icons.restaurant, color: TexconColors.darkBlue, size: 18),
                        label: Text(isLunchTakenToday ? 'LUNCH DONE' : 'START LUNCH', style: const TextStyle(fontSize: 12)),
                      ),
              ),
              const SizedBox(width: 8),

              // POST-TRIP BUTTON
              Expanded(
                child: isPostTripInProgress
                    ? FilledButton.icon(
                        onPressed: handlePostTripToggle,
                        style: FilledButton.styleFrom(backgroundColor: TexconColors.orange, padding: const EdgeInsets.symmetric(vertical: 12)),
                        icon: const Icon(Icons.check_circle_outline, size: 18),
                        label: const Text('FINISH POST-TRIP', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      )
                    : OutlinedButton.icon(
                        onPressed: (activeLoad != null || activeTimedEvent != null || isLunchInProgress) ? null : handlePostTripToggle,
                        icon: const Icon(Icons.assignment_return, color: TexconColors.red, size: 18),
                        label: const Text('POST-TRIP', style: TextStyle(fontSize: 12)),
                      ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          if (activeLoad != null) ...[
            const Text('Active Trip in Progress', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            LoadCard(
              trip: activeLoad!,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => TripDetailScreen(trip: activeLoad!, onTripUpdated: () => setState(() {}))),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: (activeTimedEvent != null || isLunchInProgress) ? null : completeActiveLoad,
              icon: const Icon(Icons.check_circle),
              label: const Text('COMPLETE LOAD', style: TextStyle(fontWeight: FontWeight.bold)),
              style: FilledButton.styleFrom(backgroundColor: TexconColors.green, minimumSize: const Size.fromHeight(50)),
            ),
          ] else ...[
            Card(
              color: TexconColors.lightBlue,
              child: const Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(Icons.local_shipping, size: 48, color: TexconColors.blue),
                    SizedBox(height: 8),
                    Text('No Active Load', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: TexconColors.darkBlue)),
                    Text('Tap below to start your next load.', style: TextStyle(color: TexconColors.grayText)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: startNewLoad,
              style: FilledButton.styleFrom(backgroundColor: TexconColors.blue, minimumSize: const Size.fromHeight(52)),
              icon: const Icon(Icons.add_location_alt),
              label: const Text('START NEW LOAD', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ],
        ],
      ],
    );
  }

  // TAB 2: DAILY LOG HISTORY
  Widget buildDailyHistoryTab() {
    final completedLoadsCount = chronologicalLog.where((e) => e.type == LogEntryType.loadTrip && e.loadTripData != null && e.loadTripData!.isCompleted).length;

    return Column(
      children: [
        // Date Selector
        Container(
          height: 56,
          color: Colors.white,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: 20,
            itemBuilder: (context, index) {
              final date = DateTime.now().subtract(Duration(days: index));
              final isSelected = date.day == selectedDate.day && date.month == selectedDate.month;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: ChoiceChip(
                  label: Text('${date.month}/${date.day}'),
                  selected: isSelected,
                  selectedColor: TexconColors.blue,
                  labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.black),
                  onSelected: (_) => setState(() => selectedDate = date),
                ),
              );
            },
          ),
        ),
        const Divider(height: 1),

        // SUMMARY HEADER
        Container(
          color: TexconColors.lightBlue,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('GROSS SHIFT HOURS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: TexconColors.grayText)),
                      Text(
                        isClockedIn ? formatHoursWorked(grossShiftDuration) : '0h 0m',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: TexconColors.darkText),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text('NET PAID HOURS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: TexconColors.grayText)),
                      Text(
                        isClockedIn ? formatHoursWorked(netPaidShiftDuration) : '0h 0m',
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: TexconColors.blue),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    hasAsphaltLoadToday
                        ? '• Asphalt Exemption: 0m Deducted'
                        : (isLunchTakenToday
                            ? '• Lunch Taken: -${calculatedLunchDeduction.inMinutes}m Deducted'
                            : '• No Lunch Taken: -30m Auto-Deducted'),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: hasAsphaltLoadToday
                          ? TexconColors.blue
                          : (isLunchTakenToday ? TexconColors.green : TexconColors.red),
                    ),
                  ),
                  Text(
                    '$completedLoadsCount Loads Completed',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: TexconColors.grayText),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // Timeline
        Expanded(
          child: chronologicalLog.isEmpty
              ? const Center(child: Text('No shift activity recorded for this day.', style: TextStyle(color: TexconColors.grayText)))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: chronologicalLog.length,
                  itemBuilder: (context, index) {
                    final log = chronologicalLog[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: buildLogCard(log),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget buildLogCard(DailyLogEntry log) {
    switch (log.type) {
      case LogEntryType.preTrip:
        return Card(
          color: Colors.white,
          child: ListTile(
            leading: const Icon(Icons.assignment_turned_in, color: TexconColors.green),
            title: Text('Pre-Trip – ${log.equipmentInfo}', style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(
              'Start: ${formatTime(log.startTime)}  ➔  End: ${log.endTime != null ? formatTime(log.endTime!) : 'In Progress'}\n'
              '${log.startingMileage != null ? 'Beginning Mileage: ${log.startingMileage} mi' : 'Mileage: N/A (Trailer Only)'}',
            ),
          ),
        );

      case LogEntryType.postTrip:
        return Card(
          color: Colors.white,
          child: ListTile(
            leading: const Icon(Icons.assignment_return, color: TexconColors.red),
            title: Text('Post-Trip – ${log.equipmentInfo}', style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(
              'Start: ${formatTime(log.startTime)}  ➔  End: ${log.endTime != null ? formatTime(log.endTime!) : 'In Progress'}\n'
              '${log.endingMileage != null ? 'Ending Mileage: ${log.endingMileage} mi' : 'Mileage: N/A (Trailer Only)'}',
            ),
          ),
        );

      case LogEntryType.standaloneActivity:
        final act = log.standaloneActivity!;
        return Card(
          color: Colors.white,
          child: ListTile(
            leading: Icon(
              act.title == 'Lunch Break' ? Icons.restaurant : Icons.free_breakfast,
              color: act.title == 'Lunch Break' ? TexconColors.darkBlue : TexconColors.blue,
            ),
            title: Text('${act.title} (Between Loads)', style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(
              'Start: ${formatTime(act.startTime)} ${act.endTime != null ? '➔ End: ${formatTime(act.endTime!)} (${formatDuration(act.duration)})' : '(In Progress...)'}',
            ),
          ),
        );

      case LogEntryType.loadTrip:
        final trip = log.loadTripData!;
        return LoadCard(
          trip: trip,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => TripDetailScreen(trip: trip, onTripUpdated: () => setState(() {}))),
          ),
          onEdit: () => editTripField(trip),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TEXCON DISPATCH', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)),
      ),
      body: currentTabIndex == 0 ? buildActiveDashboard() : buildDailyHistoryTab(),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: currentTabIndex,
        selectedItemColor: TexconColors.blue,
        onTap: (i) => setState(() => currentTabIndex = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'Active Load'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'Daily Logs (20 Days)'),
        ],
      ),
    );
  }
}

// ============================================================
// [SECTION 6: LOAD CARD WITH LUNCH TAKEN BADGE]
// ============================================================
class LoadCard extends StatelessWidget {
  final LoadTrip trip;
  final VoidCallback onTap;
  final VoidCallback? onEdit;

  const LoadCard({
    super.key,
    required this.trip,
    required this.onTap,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final int lunchMins = trip.totalLunchDuration.inMinutes;

    return Card(
      color: trip.isCompleted ? TexconColors.lightGreenCard : Colors.white,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      alignment: WrapAlignment.start,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: trip.isCompleted ? TexconColors.green.withValues(alpha: 0.15) : TexconColors.lightBlue,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'LOAD #${trip.id}  •  ${trip.gCode}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: trip.isCompleted ? TexconColors.green : TexconColors.darkBlue,
                            ),
                          ),
                        ),
                        if (trip.isCompleted)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(color: TexconColors.green, borderRadius: BorderRadius.circular(6)),
                            child: const Text('FINISHED', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                          ),

                        // --- LUNCH TAKEN BADGE ON LOAD CARD ---
                        if (trip.lunchTaken)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(color: TexconColors.darkBlue, borderRadius: BorderRadius.circular(6)),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.restaurant, color: Colors.white, size: 10),
                                const SizedBox(width: 4),
                                Text(
                                  'LUNCH TAKEN${lunchMins > 0 ? ' (${lunchMins}m)' : ''}',
                                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      Text(
                        formatDuration(trip.duration),
                        style: const TextStyle(fontFamily: 'Monospace', fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      if (onEdit != null)
                        IconButton(
                          icon: const Icon(Icons.edit_note, size: 22, color: TexconColors.blue),
                          tooltip: 'Edit Job Field',
                          onPressed: onEdit,
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(trip.jobName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text('${trip.taskCode}  |  Mat: ${trip.material}', style: const TextStyle(color: TexconColors.grayText, fontSize: 13)),
              const SizedBox(height: 6),

              // Start / Completion Timestamps
              Row(
                children: [
                  const Icon(Icons.access_time, size: 15, color: TexconColors.grayText),
                  const SizedBox(width: 4),
                  Text(
                    'Start: ${formatTime(trip.startTime)}${trip.endTime != null ? '  ➔  End: ${formatTime(trip.endTime!)}' : ''}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: TexconColors.darkText),
                  ),
                ],
              ),
              const SizedBox(height: 6),

              Row(
                children: [
                  const Icon(Icons.location_on, size: 16, color: TexconColors.blue),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '${trip.fromLocation} ➔ ${trip.gCode} - ${trip.toLocation}',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// [SECTION 7: DETAILED TRIP ACTIVITY LOG SHEET]
// ============================================================
class TripDetailScreen extends StatefulWidget {
  final LoadTrip trip;
  final VoidCallback onTripUpdated;

  const TripDetailScreen({super.key, required this.trip, required this.onTripUpdated});

  @override
  State<TripDetailScreen> createState() => _TripDetailScreenState();
}

class _TripDetailScreenState extends State<TripDetailScreen> {
  Future<void> editActivityNote(TripActivity act) async {
    final c = TextEditingController(text: act.notes);
    final note = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Edit Note for ${act.title}'),
        content: TextField(controller: c, maxLines: 3, decoration: const InputDecoration(hintText: 'Enter delay reason or notes...')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, c.text.trim()), child: const Text('Save Note')),
        ],
      ),
    );

    if (!mounted) return;
    if (note != null) {
      setState(() => act.notes = note);
      widget.onTripUpdated();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Load #${widget.trip.id} Detail Sheet'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: widget.trip.isCompleted ? TexconColors.lightGreenCard : TexconColors.lightBlue,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${widget.trip.gCode} - ${widget.trip.jobName}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: TexconColors.darkBlue)),
                  const SizedBox(height: 4),
                  Text('Task: ${widget.trip.taskCode}  |  Material: ${widget.trip.material}'),
                  Text('Route: ${widget.trip.fromLocation} ➔ ${widget.trip.gCode} - ${widget.trip.toLocation}'),
                  const Divider(height: 16),
                  Text('Start Time: ${formatTime(widget.trip.startTime)}'),
                  if (widget.trip.endTime != null) Text('Completion Time: ${formatTime(widget.trip.endTime!)}'),
                  Text('Total Elapsed: ${formatDuration(widget.trip.duration)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  if (widget.trip.lunchTaken)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('Lunch Taken During Load: ${widget.trip.totalLunchDuration.inMinutes} mins', style: const TextStyle(color: TexconColors.darkBlue, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Chronological Load Event Log', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),

          for (final act in widget.trip.activities)
            Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                title: Text(act.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Start: ${formatTime(act.startTime)} ${act.endTime != null ? '➔ End: ${formatTime(act.endTime!)} (${formatDuration(act.duration)})' : '(In Progress...)'}',
                      style: const TextStyle(fontSize: 12, color: TexconColors.grayText),
                    ),
                    if (act.notes.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('Reason/Notes: ${act.notes}', style: const TextStyle(color: TexconColors.darkBlue, fontWeight: FontWeight.bold)),
                      ),
                  ],
                ),
                trailing: act.title != 'Load Started' && act.title != 'Load Completed'
                    ? IconButton(
                        icon: const Icon(Icons.edit_note, color: TexconColors.blue),
                        onPressed: () => editActivityNote(act),
                      )
                    : null,
              ),
            ),
        ],
      ),
    );
  }
}