import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const DurianScaleApp());
}

class DurianScaleApp extends StatefulWidget {
  const DurianScaleApp({super.key});

  @override
  State<DurianScaleApp> createState() => _DurianScaleAppState();
}

class _DurianScaleAppState extends State<DurianScaleApp> {
  ThemeMode _themeMode = ThemeMode.dark;

  void toggleTheme() {
    setState(() {
      _themeMode = _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cân Sầu Riêng Pro',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFE2E8F0),
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF15803D),
          surface: Colors.white,
          onSurface: Color(0xFF0F172A),
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF22C55E),
          surface: Color(0xFF121214),
          onSurface: Colors.white,
        ),
        useMaterial3: true,
      ),
      home: MainScaleScreen(
        onToggleTheme: toggleTheme,
        isDark: _themeMode == ThemeMode.dark,
      ),
    );
  }
}

class WeighingItem {
  final double gross;
  final double tare;
  final double net;

  WeighingItem({required this.gross, required this.tare, required this.net});

  Map<String, dynamic> toJson() => {'gross': gross, 'tare': tare, 'net': net};
  factory WeighingItem.fromJson(Map<String, dynamic> json) => WeighingItem(
        gross: (json['gross'] as num).toDouble(),
        tare: (json['tare'] as num).toDouble(),
        net: (json['net'] as num).toDouble(),
      );
}

class WeighingSession {
  String id;
  String name;
  String farmer;
  String truck;
  double price;
  double deposit;
  double tare;
  String createdAt;
  int currentIdx;
  List<WeighingItem?> items;

  WeighingSession({
    required this.id,
    required this.name,
    required this.farmer,
    required this.truck,
    required this.price,
    this.deposit = 0.0,
    this.tare = 0.0,
    required this.createdAt,
    this.currentIdx = 0,
    required this.items,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'farmer': farmer,
        'truck': truck,
        'price': price,
        'deposit': deposit,
        'tare': tare,
        'createdAt': createdAt,
        'currentIdx': currentIdx,
        'items': items.map((e) => e?.toJson()).toList(),
      };

  factory WeighingSession.fromJson(Map<String, dynamic> json) => WeighingSession(
        id: json['id'],
        name: json['name'],
        farmer: json['farmer'],
        truck: json['truck'] ?? 'Xe 01',
        price: (json['price'] as num).toDouble(),
        deposit: (json['deposit'] as num?)?.toDouble() ?? 0.0,
        tare: (json['tare'] as num?)?.toDouble() ?? 0.0,
        createdAt: json['createdAt'],
        currentIdx: json['currentIdx'] ?? 0,
        items: (json['items'] as List)
            .map((e) => e == null ? null : WeighingItem.fromJson(e))
            .toList(),
      );
}

class MainScaleScreen extends StatefulWidget {
  final VoidCallback onToggleTheme;
  final bool isDark;

  const MainScaleScreen({super.key, required this.onToggleTheme, required this.isDark});

  @override
  State<MainScaleScreen> createState() => _MainScaleScreenState();
}

class _MainScaleScreenState extends State<MainScaleScreen> {
  static const int colsPerSheet = 8;
  static const int rowsPerCol = 5;
  static const int slotsPerSheet = colsPerSheet * rowsPerCol;

  List<WeighingSession> _sessions = [];
  late WeighingSession _activeSession;
  String _buffer = "";
  int _viewSheetIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final dataStr = prefs.getString('durian_scale_native_v1');
    if (dataStr != null) {
      try {
        final list = jsonDecode(dataStr) as List;
        _sessions = list.map((e) => WeighingSession.fromJson(e)).toList();
      } catch (_) {}
    }

    if (_sessions.isEmpty) {
      final now = DateTime.now();
      _activeSession = WeighingSession(
        id: "sess_${now.millisecondsSinceEpoch}",
        name: "Đợt 1",
        farmer: "Vườn chú Tài",
        truck: "Xe 01",
        price: 75000,
        createdAt: DateFormat('HH:mm dd/MM/yyyy').format(now),
        items: List.filled(slotsPerSheet, null),
      );
      _sessions.add(_activeSession);
    } else {
      _activeSession = _sessions.first;
    }

    _ensureCapacity();
    _viewSheetIndex = _activeSession.currentIdx ~/ slotsPerSheet;
    setState(() {});
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final dataStr = jsonEncode(_sessions.map((e) => e.toJson()).toList());
    await prefs.setString('durian_scale_native_v1', dataStr);
  }

  void _ensureCapacity() {
    final curSheets = (_activeSession.items.length / slotsPerSheet).ceil();
    final target = (curSheets < 1 ? 1 : curSheets) * slotsPerSheet;
    while (_activeSession.items.length < target) {
      _activeSession.items.add(null);
    }
  }

  void _pressKey(String char) {
    setState(() {
      _buffer += char;
      if (_buffer.length == 3) {
        final gross = double.parse(_buffer) / 10.0;
        _commitValue(gross);
      }
    });
  }

  void _pressDot() {
    if (!_buffer.contains('.')) {
      setState(() => _buffer += '.');
    }
  }

  void _commitValue(double gross) {
    HapticFeedback.heavyImpact();
    final net = (gross - _activeSession.tare).clamp(0.0, 999.0);
    _activeSession.items[_activeSession.currentIdx] =
        WeighingItem(gross: gross, tare: _activeSession.tare, net: net);
    _buffer = "";

    if (_activeSession.currentIdx + 1 >= _activeSession.items.length) {
      _activeSession.items.addAll(List.filled(slotsPerSheet, null));
    }
    _activeSession.currentIdx++;
    _viewSheetIndex = _activeSession.currentIdx ~/ slotsPerSheet;
    _persist();
    setState(() {});
  }

  void _backspace() {
    setState(() {
      if (_buffer.isNotEmpty) {
        _buffer = _buffer.substring(0, _buffer.length - 1);
      } else if (_activeSession.currentIdx > 0) {
        _activeSession.currentIdx--;
        _viewSheetIndex = _activeSession.currentIdx ~/ slotsPerSheet;
      }
    });
  }

  void _clearCurrent() {
    setState(() {
      _activeSession.items[_activeSession.currentIdx] = null;
      _buffer = "";
      _persist();
    });
  }

  void _manualConfirm() {
    if (_buffer.isNotEmpty) {
      _commitValue(double.tryParse(_buffer) ?? 0.0);
    } else if (_activeSession.currentIdx + 1 < _activeSession.items.length) {
      setState(() {
        _activeSession.currentIdx++;
        _viewSheetIndex = _activeSession.currentIdx ~/ slotsPerSheet;
      });
    }
  }

  double get _totalNetAll =>
      _activeSession.items.whereType<WeighingItem>().fold(0.0, (sum, e) => sum + e.net);

  int get _totalCountAll =>
      _activeSession.items.whereType<WeighingItem>().length;

  @override
  Widget build(BuildContext context) {
    final isLandscape = MediaQuery.of(context).size.width > 680;
    final totalSheets = (_activeSession.items.length / slotsPerSheet).ceil();

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 48,
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Row(
          children: [
            _buildHeaderTag("Bì: ${_activeSession.tare.toStringAsFixed(1)}k", onTap: _setTarePrompt),
            const SizedBox(width: 6),
            _buildHeaderTag("Tổng: $_totalCountAll mã"),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(widget.isDark ? Icons.light_mode : Icons.dark_mode, size: 20),
            onPressed: widget.onToggleTheme,
          ),
          TextButton(
            onPressed: _openSessionsDialog,
            child: const Text("📁 Đợt Cân", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          TextButton(
            onPressed: _openConfigDialog,
            child: const Text("Cài Đặt", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFACC15),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            ),
            onPressed: _openSummaryDialog,
            child: const Text("Toa Cân", style: TextStyle(fontWeight: FontWeight.w900)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: isLandscape
            ? Row(
                children: [
                  Expanded(flex: 5, child: _buildSheetArea(totalSheets)),
                  const VerticalDivider(width: 1),
                  Expanded(flex: 4, child: _buildControlPadArea()),
                ],
              )
            : Column(
                children: [
                  Expanded(child: _buildSheetArea(totalSheets)),
                  _buildControlPadArea(),
                ],
              ),
      ),
    );
  }

  Widget _buildHeaderTag(String text, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF202024)
              : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.grey.withOpacity(0.3)),
        ),
        child: Text(
          text,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
      ),
    );
  }

  Widget _buildSheetArea(int totalSheets) {
    final startIdx = _viewSheetIndex * slotsPerSheet;
    final endIdx = startIdx + slotsPerSheet;

    double sheetSum = 0.0;
    List<double> colSums = List.filled(colsPerSheet, 0.0);
    List<int> colFilled = List.filled(colsPerSheet, 0);

    for (int c = 0; c < colsPerSheet; c++) {
      for (int r = 0; r < rowsPerCol; r++) {
        final idx = startIdx + (c * rowsPerCol + r);
        if (idx < _activeSession.items.length) {
          final it = _activeSession.items[idx];
          if (it != null) {
            sheetSum += it.net;
            colSums[c] += it.net;
            colFilled[c]++;
          }
        }
      }
    }

    return Padding(
      padding: const EdgeInsets.all(4.0),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_left, size: 28),
                      onPressed: _viewSheetIndex > 0
                          ? () => setState(() => _viewSheetIndex--)
                          : null,
                    ),
                    Text(
                      "BẢNG ${_viewSheetIndex + 1}/$totalSheets (#${startIdx + 1} - #${endIdx})",
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                    ),
                    IconButton(
                      icon: const Icon(Icons.arrow_right, size: 28),
                      onPressed: _viewSheetIndex < totalSheets - 1
                          ? () => setState(() => _viewSheetIndex++)
                          : null,
                    ),
                  ],
                ),
                Text(
                  "${sheetSum.toStringAsFixed(1)} kg",
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: List.generate(colsPerSheet, (col) {
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1.5),
                      child: Column(
                        children: [
                          ...List.generate(rowsPerCol, (row) {
                            final idx = startIdx + (col * rowsPerCol + row);
                            final isFocus = idx == _activeSession.currentIdx;
                            final item = idx < _activeSession.items.length
                                ? _activeSession.items[idx]
                                : null;

                            return Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() {
                                  _activeSession.currentIdx = idx;
                                  _buffer = "";
                                }),
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 3),
                                  decoration: BoxDecoration(
                                    color: isFocus
                                        ? const Color(0xFFFACC15)
                                        : (item != null
                                            ? (Theme.of(context).brightness == Brightness.dark
                                                ? const Color(0xFF18181C)
                                                : const Color(0xFFF8FAFC))
                                            : Theme.of(context).colorScheme.surface),
                                    border: Border.all(
                                      color: isFocus
                                          ? const Color(0xFFFACC15)
                                          : Colors.grey.withOpacity(0.3),
                                      width: isFocus ? 2 : 1,
                                    ),
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: Stack(
                                    children: [
                                      Positioned(
                                        top: 2,
                                        left: 3,
                                        child: Text(
                                          "#${idx + 1}",
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                            color: isFocus
                                                ? const Color(0xFF713F12)
                                                : Colors.grey,
                                          ),
                                        ),
                                      ),
                                      Center(
                                        child: Text(
                                          item != null ? item.net.toStringAsFixed(1) : "",
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w900,
                                            color: isFocus ? Colors.black : null,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }),
                          Container(
                            height: 34,
                            decoration: BoxDecoration(
                              color: colFilled[col] == 5
                                  ? const Color(0xFFFEF08A).withOpacity(0.2)
                                  : Colors.transparent,
                              border: Border.all(
                                color: colFilled[col] == 5
                                    ? const Color(0xFFEAB308)
                                    : Colors.grey.withOpacity(0.25),
                                style: BorderStyle.solid,
                              ),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  "C${col + 1}",
                                  style: TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.bold,
                                    color: colFilled[col] == 5
                                        ? const Color(0xFFEAB308)
                                        : Colors.grey,
                                  ),
                                ),
                                Text(
                                  colFilled[col] > 0
                                      ? colSums[col].toStringAsFixed(1)
                                      : "--",
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w900,
                                    color: colFilled[col] == 5
                                        ? const Color(0xFFEAB308)
                                        : Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlPadArea() {
    final displayBuffer = _buffer.isEmpty
        ? "0"
        : (_buffer.length < 3
            ? _buffer
            : (double.parse(_buffer) / 10.0).toStringAsFixed(1));

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: Colors.grey.withOpacity(0.2))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    "Mã #${_activeSession.currentIdx + 1}: ",
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
                  ),
                  Text(
                    displayBuffer,
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const Text(" kg", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      "TỔNG KÝ ĐỢT CÂN",
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey),
                    ),
                    Text(
                      "${_totalNetAll.toStringAsFixed(1)} KG",
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFFEAB308),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "${_activeSession.farmer} - ${_activeSession.name} (${_activeSession.truck})",
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const Text(
                  "Tạo bởi: letuananhbmt",
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFEAB308)),
                ),
              ],
            ),
          ),
          _buildNumericKeypad(),
        ],
      ),
    );
  }

  Widget _buildNumericKeypad() {
    return SizedBox(
      height: 210,
      child: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                _buildKey("7", () => _pressKey("7")),
                _buildKey("8", () => _pressKey("8")),
                _buildKey("9", () => _pressKey("9")),
                _buildKey("⌫", _backspace, isAction: true),
              ],
            ),
          ),
          Expanded(
            child: Row(
              children: [
                _buildKey("4", () => _pressKey("4")),
                _buildKey("5", () => _pressKey("5")),
                _buildKey("6", () => _pressKey("6")),
                _buildKey("XÓA", _clearCurrent, isDanger: true),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            _buildKey("1", () => _pressKey("1")),
                            _buildKey("2", () => _pressKey("2")),
                            _buildKey("3", () => _pressKey("3")),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Row(
                          children: [
                            _buildKey("0", () => _pressKey("0"), flex: 2),
                            _buildKey(".", _pressDot),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                _buildKey("LƯU", _manualConfirm, isEnter: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKey(String label, VoidCallback onTap,
      {int flex = 1, bool isAction = false, bool isDanger = false, bool isEnter = false}) {
    Color bg = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF1E1E22)
        : Colors.white;
    Color fg = Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white;

    if (isAction) {
      bg = Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF2B2B30)
          : const Color(0xFFF1F5F9);
    }
    if (isDanger) {
      bg = const Color(0xFF451A1A);
      fg = const Color(0xFFF87171);
    }
    if (isEnter) {
      bg = const Color(0xFF15803D);
      fg = Colors.white;
    }

    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.all(2.5),
        child: Material(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          elevation: 1,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTap,
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: isEnter || isDanger ? 17 : 24,
                  fontWeight: FontWeight.w900,
                  color: fg,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _setTarePrompt() {
    final controller = TextEditingController(text: _activeSession.tare.toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Trừ bì mặc định (kg)"),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: "Nhập số kg bì"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Hủy")),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _activeSession.tare = double.tryParse(controller.text) ?? 0.0;
                _persist();
              });
              Navigator.pop(ctx);
            },
            child: const Text("Lưu"),
          ),
        ],
      ),
    );
  }

  void _openSessionsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text("Danh Sách Đợt Cân"),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(40),
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text("TẠO ĐỢT CÂN MỚI"),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _openCreateSessionDialog();
                  },
                ),
                const SizedBox(height: 10),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _sessions.length,
                    itemBuilder: (context, i) {
                      final s = _sessions[i];
                      final isCurrent = s.id == _activeSession.id;
                      final totalNet = s.items.whereType<WeighingItem>().fold(0.0, (sum, e) => sum + e.net);

                      return Card(
                        color: isCurrent ? Colors.green.withOpacity(0.15) : null,
                        child: ListTile(
                          title: Text("${s.name} - ${s.farmer} (${s.truck})",
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(
                              "${s.createdAt} | ${s.items.whereType<WeighingItem>().length} mã | ${totalNet.toStringAsFixed(1)} kg"),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!isCurrent)
                                IconButton(
                                  icon: const Icon(Icons.open_in_new, color: Colors.blue),
                                  onPressed: () {
                                    setState(() {
                                      _activeSession = s;
                                      _ensureCapacity();
                                      _viewSheetIndex = _activeSession.currentIdx ~/ slotsPerSheet;
                                      _persist();
                                    });
                                    Navigator.pop(ctx);
                                  },
                                ),
                              if (_sessions.length > 1)
                                IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.red),
                                  onPressed: () {
                                    setState(() {
                                      _sessions.removeAt(i);
                                      if (isCurrent) _activeSession = _sessions.first;
                                      _persist();
                                    });
                                    setDialogState(() {});
                                  },
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Đóng")),
          ],
        ),
      ),
    );
  }

  void _openCreateSessionDialog() {
    final nameCtrl = TextEditingController(text: "Đợt ${_sessions.length + 1}");
    final farmerCtrl = TextEditingController(text: _activeSession.farmer);
    final truckCtrl = TextEditingController(text: _activeSession.truck);
    final priceCtrl = TextEditingController(text: _activeSession.price.toStringAsFixed(0));

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Tạo Đợt Cân Mới"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "Tên đợt cân")),
            TextField(controller: farmerCtrl, decoration: const InputDecoration(labelText: "Tên vườn")),
            TextField(controller: truckCtrl, decoration: const InputDecoration(labelText: "Xe cân")),
            TextField(
              controller: priceCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "Đơn giá (đ/kg)"),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Hủy")),
          ElevatedButton(
            onPressed: () {
              final now = DateTime.now();
              final newSess = WeighingSession(
                id: "sess_${now.millisecondsSinceEpoch}",
                name: nameCtrl.text.trim(),
                farmer: farmerCtrl.text.trim(),
                truck: truckCtrl.text.trim(),
                price: double.tryParse(priceCtrl.text) ?? 75000,
                createdAt: DateFormat('HH:mm dd/MM/yyyy').format(now),
                items: List.filled(slotsPerSheet, null),
              );
              setState(() {
                _sessions.insert(0, newSess);
                _activeSession = newSess;
                _viewSheetIndex = 0;
                _persist();
              });
              Navigator.pop(ctx);
            },
            child: const Text("Tạo & Vào Cân"),
          ),
        ],
      ),
    );
  }

  void _openConfigDialog() {
    final nameCtrl = TextEditingController(text: _activeSession.name);
    final farmerCtrl = TextEditingController(text: _activeSession.farmer);
    final truckCtrl = TextEditingController(text: _activeSession.truck);
    final priceCtrl = TextEditingController(text: _activeSession.price.toStringAsFixed(0));
    final depositCtrl = TextEditingController(text: _activeSession.deposit.toStringAsFixed(0));
    final tareCtrl = TextEditingController(text: _activeSession.tare.toString());

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Cấu Hình Đợt Cân"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "Tên đợt")),
              TextField(controller: farmerCtrl, decoration: const InputDecoration(labelText: "Tên vườn")),
              TextField(controller: truckCtrl, decoration: const InputDecoration(labelText: "Xe cân")),
              TextField(controller: priceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Đơn giá (đ/kg)")),
              TextField(controller: depositCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Tiền cọc (VNĐ)")),
              TextField(controller: tareCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Trừ bì (kg)")),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Hủy")),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _activeSession.name = nameCtrl.text.trim();
                _activeSession.farmer = farmerCtrl.text.trim();
                _activeSession.truck = truckCtrl.text.trim();
                _activeSession.price = double.tryParse(priceCtrl.text) ?? 75000;
                _activeSession.deposit = double.tryParse(depositCtrl.text) ?? 0.0;
                _activeSession.tare = double.tryParse(tareCtrl.text) ?? 0.0;
                _persist();
              });
              Navigator.pop(ctx);
            },
            child: const Text("Lưu"),
          ),
        ],
      ),
    );
  }

  void _openSummaryDialog() {
    final totalNet = _totalNetAll;
    final totalMoney = totalNet * _activeSession.price;
    final remain = totalMoney - _activeSession.deposit;
    final formatCurrency = NumberFormat("#,##0", "vi_VN");

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Toa Cân Chi Tiết"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Đợt cân: ${_activeSession.name} (${_activeSession.truck})"),
            Text("Nhà vườn: ${_activeSession.farmer}"),
            Text("Đơn giá: ${formatCurrency.format(_activeSession.price)} đ/kg"),
            Text("Tổng số mã: $_totalCountAll sọt"),
            const Divider(),
            Text("Tổng khối lượng: ${totalNet.toStringAsFixed(1)} kg", style: const TextStyle(fontWeight: FontWeight.bold)),
            Text("Thành tiền: ${formatCurrency.format(totalMoney)} VNĐ", style: const TextStyle(fontWeight: FontWeight.bold)),
            Text("Đã cọc trước: -${formatCurrency.format(_activeSession.deposit)} VNĐ"),
            const SizedBox(height: 6),
            Text("CÒN LẠI: ${formatCurrency.format(remain)} VNĐ",
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Colors.green)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Đóng")),
          ElevatedButton.icon(
            icon: const Icon(Icons.print),
            label: const Text("In Biên Bản Cân"),
            onPressed: () {
              Navigator.pop(ctx);
              _printOfficialAdministrativeDoc();
            },
          ),
        ],
      ),
    );
  }

  void _printOfficialAdministrativeDoc() async {
    final pdf = pw.Document();
    final formatCurrency = NumberFormat("#,##0", "vi_VN");
    final totalNet = _totalNetAll;
    final totalMoney = totalNet * _activeSession.price;
    final remain = totalMoney - _activeSession.deposit;
    final now = DateTime.now();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (context) => [
          pw.Center(
            child: pw.Column(
              children: [
                pw.Text("CONG HOA XA HOI CHU NGHIA VIET NAM",
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                pw.Text("Doc lap - Tu do - Hanh phuc",
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
                pw.Container(width: 140, height: 1, color: PdfColors.black, margin: const pw.EdgeInsets.only(top: 2, bottom: 12)),
                pw.Text("BIEN BAN CHOT SO LUONG VA TRONG LUONG SAU RIENG",
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13)),
                pw.Text("Ngay ${now.day} thang ${now.month} nam ${now.year}",
                    style: const pw.TextStyle(fontSize: 10, fontStyle: pw.FontStyle.italic)),
              ],
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Text("I. CAC BEN THAM GIA GIAO NHAN", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
          pw.Text("1. Ben Ban (Chu vuon): ${_activeSession.farmer}"),
          pw.Text("2. Ben Mua (Xe can): ${_activeSession.truck} - Dot: ${_activeSession.name}"),
          pw.Text("   Don gia thoa thuan: ${formatCurrency.format(_activeSession.price)} VND/kg"),
          pw.SizedBox(height: 8),
          pw.Text("II. CHI TIET SO LIEU CAN (Tong so sot: $_totalCountAll sot)",
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
          pw.SizedBox(height: 4),
          _buildPdfWeighingGrid(),
          pw.SizedBox(height: 8),
          pw.Text("III. TONG HOP GIA TRI DON HANG", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
          pw.Text("- Tong trong luong thuc te: ${totalNet.toStringAsFixed(1)} kg"),
          pw.Text("- Tong thanh tien: ${formatCurrency.format(totalMoney)} VND"),
          pw.Text("- So tien da dat coc truoc: ${formatCurrency.format(_activeSession.deposit)} VND"),
          pw.Text("- SO TIEN CON LAI PHAI THANH TOAN: ${formatCurrency.format(remain)} VND",
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
          pw.SizedBox(height: 8),
          pw.Text("IV. CAM KET CHUNG: Hai ben dong y voi so luong tren va thanh toan day du.",
              style: const pw.TextStyle(fontSize: 9, fontStyle: pw.FontStyle.italic)),
          pw.SizedBox(height: 16),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                children: [
                  pw.Text("DAI DIEN BEN BAN", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                  pw.SizedBox(height: 40),
                  pw.Text(_activeSession.farmer, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                ],
              ),
              pw.Column(
                children: [
                  pw.Text("DAI DIEN BEN MUA", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                  pw.SizedBox(height: 40),
                  pw.Text("......................................", style: const pw.TextStyle(fontSize: 10)),
                ],
              ),
            ],
          ),
        ],
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }

  pw.Widget _buildPdfWeighingGrid() {
    final items = _activeSession.items.whereType<WeighingItem>().toList();
    const cols = 8;
    final rowCount = (items.length / cols).ceil();

    return pw.Table(
      border: pw.TableBorder.all(width: 0.5, color: PdfColors.black),
      children: List.generate(rowCount < 1 ? 1 : rowCount, (r) {
        return pw.TableRow(
          children: List.generate(cols, (c) {
            final idx = r * cols + c;
            final it = idx < items.length ? items[idx] : null;
            return pw.Container(
              padding: const pw.EdgeInsets.all(2),
              alignment: pw.Alignment.center,
              child: pw.Text(
                it != null ? "#${idx + 1}: ${it.net.toStringAsFixed(1)}" : "-",
                style: const pw.TextStyle(fontSize: 7.5),
              ),
            );
          }),
        );
      }),
    );
  }
}
