import re

with open('lib/screens/sessions_screen.dart', 'r', encoding='utf-8') as f:
    code = f.read()

state_vars = """
  List<dynamic> _historySessions = [];
  List<dynamic> _filteredHistorySessions = [];

  // Filter State
  DateTimeRange? _filterDateRange;
  String _sortBy = 'Session Start'; // 'Session Start', 'Session End'
  bool _sortAscending = false;
  String? _filterYard;
  String? _filterPilot;
  String _filterDeviceId = '';
  double _filterDurationValue = 0; // minutes
  String _filterDurationOperator = '>'; // '>', '<', '='
"""
code = code.replace("  List<dynamic> _historySessions = [];", state_vars)

fetch_history = """
        if (!isSame || _isLoadingHistory) {
          setState(() {
            _historySessions = newHistory;
            _isLoadingHistory = false;
          });
          _applyFilters();
        }
"""
code = code.replace("""
        if (!isSame || _isLoadingHistory) {
          setState(() {
            _historySessions = newHistory;
            _isLoadingHistory = false;
          });
        }
""", fetch_history)

apply_filters = """
  void _applyFilters() {
    List<dynamic> filtered = List.from(_historySessions);

    if (_filterDateRange != null) {
      filtered = filtered.where((s) {
        try {
          final st = DateTime.parse(s['startTime'] ?? s['created_at'] ?? '').toLocal();
          return st.isAfter(_filterDateRange!.start) && st.isBefore(_filterDateRange!.end.add(const Duration(days: 1)));
        } catch (_) { return false; }
      }).toList();
    }

    if (_filterYard != null && _filterYard!.isNotEmpty) {
      filtered = filtered.where((s) => (s['yard'] ?? s['yard_name']) == _filterYard).toList();
    }
    
    if (_filterPilot != null && _filterPilot!.isNotEmpty) {
      filtered = filtered.where((s) => (s['holder'] ?? s['employee_name']) == _filterPilot).toList();
    }

    if (_filterDeviceId.isNotEmpty) {
      final search = _filterDeviceId.toLowerCase();
      filtered = filtered.where((s) {
        final rx = (s['ldDevice'] ?? s['rx_device_id'] ?? '').toString().toLowerCase();
        final tx = (s['deDevice'] ?? s['tx_device_id'] ?? '').toString().toLowerCase();
        return rx.contains(search) || tx.contains(search);
      }).toList();
    }

    if (_filterDurationValue > 0) {
      filtered = filtered.where((s) {
        double durationMins = 0;
        if (s['startTime'] != null && s['endTime'] != null) {
          try {
            final st = DateTime.parse(s['startTime']);
            final et = DateTime.parse(s['endTime']);
            durationMins = et.difference(st).inMinutes.toDouble();
          } catch (_) {}
        } else if (s['duration'] != null) {
           final durStr = s['duration'].toString();
           final hMatch = RegExp(r'(\\d+)h').firstMatch(durStr);
           if (hMatch != null) durationMins += int.parse(hMatch.group(1)!) * 60;
           final mMatch = RegExp(r'(\\d+)m').firstMatch(durStr);
           if (mMatch != null) durationMins += int.parse(mMatch.group(1)!);
        }

        if (_filterDurationOperator == '>') return durationMins > _filterDurationValue;
        if (_filterDurationOperator == '<') return durationMins < _filterDurationValue;
        if (_filterDurationOperator == '=') return (durationMins - _filterDurationValue).abs() <= 5;
        return true;
      }).toList();
    }

    filtered.sort((a, b) {
      DateTime timeA;
      DateTime timeB;
      if (_sortBy == 'Session End') {
        timeA = DateTime.tryParse(a['endTime'] ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
        timeB = DateTime.tryParse(b['endTime'] ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
      } else {
        timeA = DateTime.tryParse(a['startTime'] ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
        timeB = DateTime.tryParse(b['startTime'] ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
      }
      return _sortAscending ? timeA.compareTo(timeB) : timeB.compareTo(timeA);
    });

    setState(() {
      _filteredHistorySessions = filtered;
    });
  }

  Future<void> _fetchData() async {"""
code = code.replace("  Future<void> _fetchData() async {", apply_filters)


# Use regex to replace _buildHistoryTab and _showRangeReportDialog with new implementations
build_history = """  Widget _buildHistoryTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
          child: _buildFilterBar(),
        ),
        Expanded(
          child: _filteredHistorySessions.isEmpty
              ? const Center(
                  child: Text(
                    'No past shunting sessions found matching the criteria.',
                    style: TextStyle(color: Colors.white38),
                  ),
                )
              : ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 12.0),
                  itemCount: _filteredHistorySessions.length,
                  itemBuilder: (context, index) {
                    return _buildHistorySessionItem(_filteredHistorySessions[index]);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Date Range
          Expanded(
            child: InkWell(
              onTap: () async {
                final picked = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2024),
                  lastDate: DateTime.now(),
                  initialDateRange: _filterDateRange,
                  builder: (context, child) => Theme(
                    data: ThemeData.dark().copyWith(
                      colorScheme: const ColorScheme.dark(
                        primary: Colors.cyanAccent,
                        onPrimary: Colors.black,
                        surface: Color(0xFF1E293B),
                      ),
                    ),
                    child: child!,
                  ),
                );
                if (picked != null) {
                  setState(() => _filterDateRange = picked);
                  _applyFilters();
                }
              },
              child: Row(
                children: [
                  const Icon(Icons.date_range, color: Colors.cyanAccent, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _filterDateRange == null
                          ? 'Select Date Range'
                          : '${_filterDateRange!.start.day}/${_filterDateRange!.start.month} - ${_filterDateRange!.end.day}/${_filterDateRange!.end.month}',
                      style: TextStyle(color: _filterDateRange == null ? Colors.white54 : Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_filterDateRange != null)
                    GestureDetector(
                      onTap: () {
                        setState(() => _filterDateRange = null);
                        _applyFilters();
                      },
                      child: const Icon(Icons.clear, size: 16, color: Colors.white54),
                    ),
                ],
              ),
            ),
          ),
          // Actions
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.filter_list, size: 22, color: Colors.white),
                onPressed: _showAdvancedFilterSheet,
                tooltip: 'Advanced Filters & Sorting',
              ),
              IconButton(
                icon: const Icon(Icons.picture_as_pdf, size: 22, color: Colors.redAccent),
                onPressed: () => _downloadFilteredReport(isExcel: false),
                tooltip: 'Download Filtered PDF',
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showAdvancedFilterSheet() {
    final yards = _historySessions.map((s) => (s['yard'] ?? s['yard_name'])?.toString()).where((s) => s != null && s.isNotEmpty).toSet().toList();
    final pilots = _historySessions.map((s) => (s['holder'] ?? s['employee_name'])?.toString()).where((s) => s != null && s.isNotEmpty).toSet().toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 20, right: 20, top: 20),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Advanced Filters & Sorting', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    const Divider(color: Colors.white24, height: 30),
                    
                    // Sort By
                    const Text('Sort By', style: TextStyle(color: Colors.cyanAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _sortBy,
                            dropdownColor: const Color(0xFF1E293B),
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                            decoration: InputDecoration(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              filled: true,
                              fillColor: const Color(0xFF1E293B),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                            ),
                            items: ['Session Start', 'Session End'].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                            onChanged: (v) => setSheetState(() => _sortBy = v!),
                          ),
                        ),
                        const SizedBox(width: 10),
                        InkWell(
                          onTap: () => setSheetState(() => _sortAscending = !_sortAscending),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(8)),
                            child: Icon(_sortAscending ? Icons.arrow_upward : Icons.arrow_downward, color: Colors.cyanAccent, size: 20),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Yard & Pilot
                    const Text('Attributes', style: TextStyle(color: Colors.cyanAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String?>(
                      value: _filterYard,
                      dropdownColor: const Color(0xFF1E293B),
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        labelText: 'Yard',
                        labelStyle: const TextStyle(color: Colors.white54),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        filled: true,
                        fillColor: const Color(0xFF1E293B),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      ),
                      items: [
                        const DropdownMenuItem<String?>(value: null, child: Text('All Yards')),
                        ...yards.map((s) => DropdownMenuItem(value: s, child: Text(s!))),
                      ],
                      onChanged: (v) => setSheetState(() => _filterYard = v),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String?>(
                      value: _filterPilot,
                      dropdownColor: const Color(0xFF1E293B),
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        labelText: 'Loco Pilot',
                        labelStyle: const TextStyle(color: Colors.white54),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        filled: true,
                        fillColor: const Color(0xFF1E293B),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      ),
                      items: [
                        const DropdownMenuItem<String?>(value: null, child: Text('All Pilots')),
                        ...pilots.map((s) => DropdownMenuItem(value: s, child: Text(s!))),
                      ],
                      onChanged: (v) => setSheetState(() => _filterPilot = v),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      initialValue: _filterDeviceId,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        labelText: 'Device ID (e.g. RX-01)',
                        labelStyle: const TextStyle(color: Colors.white54),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        filled: true,
                        fillColor: const Color(0xFF1E293B),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      ),
                      onChanged: (v) => setSheetState(() => _filterDeviceId = v),
                    ),
                    const SizedBox(height: 20),

                    // Duration
                    const Text('Duration (Minutes)', style: TextStyle(color: Colors.cyanAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        DropdownButton<String>(
                          value: _filterDurationOperator,
                          dropdownColor: const Color(0xFF1E293B),
                          style: const TextStyle(color: Colors.cyanAccent, fontSize: 16, fontWeight: FontWeight.bold),
                          underline: const SizedBox(),
                          items: ['>', '<', '='].map((op) => DropdownMenuItem(value: op, child: Text(op))).toList(),
                          onChanged: (v) => setSheetState(() => _filterDurationOperator = v!),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Slider(
                            value: _filterDurationValue,
                            min: 0,
                            max: 240,
                            divisions: 24,
                            activeColor: Colors.cyanAccent,
                            inactiveColor: Colors.white24,
                            label: '${_filterDurationValue.toInt()} mins',
                            onChanged: (v) => setSheetState(() => _filterDurationValue = v),
                          ),
                        ),
                        Text('${_filterDurationValue.toInt()}m', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 30),
                    
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.cyanAccent.shade700,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () {
                          setState(() {});
                          _applyFilters();
                          Navigator.pop(ctx);
                        },
                        child: const Text('Apply Filters', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _downloadFilteredReport({bool isExcel = false}) async {
    if (_filteredHistorySessions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No sessions to download. Adjust filters.'), backgroundColor: Colors.orange));
      return;
    }
    
    DateTime? from = _filterDateRange?.start;
    DateTime? to = _filterDateRange?.end;
    
    if (from == null || to == null) {
       List<DateTime> dates = _filteredHistorySessions.map((s) {
         try {
           return DateTime.parse(s['startTime'] ?? s['created_at'] ?? '');
         } catch (_) { return DateTime.now(); }
       }).toList();
       if (dates.isNotEmpty) {
          dates.sort();
          from = dates.first;
          to = dates.last;
       } else {
          from = DateTime.now().subtract(const Duration(days: 1));
          to = DateTime.now();
       }
    }
    
    final fromStr = '${from.year}-${from.month.toString().padLeft(2,'0')}-${from.day.toString().padLeft(2,'0')}';
    final toStr = '${to.year}-${to.month.toString().padLeft(2,'0')}-${to.day.toString().padLeft(2,'0')}';
    
    String query = 'from_date=$fromStr&to_date=$toStr';
    if (_filterYard != null) query += '&yard=${Uri.encodeComponent(_filterYard!)}';
    if (_filterPilot != null) query += '&pilot=${Uri.encodeComponent(_filterPilot!)}';
    if (_filterDeviceId.isNotEmpty) query += '&device=${Uri.encodeComponent(_filterDeviceId)}';
    if (_filterDurationValue > 0) query += '&dur_op=${Uri.encodeComponent(_filterDurationOperator)}&dur_val=$_filterDurationValue';
    query += '&sort_by=${Uri.encodeComponent(_sortBy)}&sort_asc=$_sortAscending';

    // Instead of directly using ApiService logic, construct the correct report URL
    final token = await UserSession().token ?? '';
    final url = '${ApiService.baseUrl}/reports/range/pdf?$query&token=$token';
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Generating Filtered Report...'), backgroundColor: Color(0xFF003580)),
    );
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.redAccent));
    }
  }

"""

code = re.sub(r'  Widget _buildHistoryTab\(\) \{.*?\n  Widget _buildHistorySessionItem', build_history + "\n  Widget _buildHistorySessionItem", code, flags=re.DOTALL)


with open('lib/screens/sessions_screen.dart', 'w', encoding='utf-8') as f:
    f.write(code)

print("Done")
