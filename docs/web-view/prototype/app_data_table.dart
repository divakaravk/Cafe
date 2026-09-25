// Prototype of the app-level data table ("datacell" grid) for the web/desktop layouts.
// Built on data_table_2 (2.7.2 = newest release that resolves on Flutter 3.35.6).
//
//   * wide windows  -> sticky-header, sortable, paginated table with row actions
//   * compact (<720)-> the same rows as tappable cards (touch-friendly)
//   * columns can hide themselves below a window class (responsive columns)
import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';

// Callers import only this file, never data_table_2 directly => the library stays swappable.
export 'package:data_table_2/data_table_2.dart' show ColumnSize;

/// Material 3 window-size classes. The single source of truth for breakpoints
/// (replaces the literals 600/700/720/800/850/1100/1200/1400 spread over ~10 files).
enum WindowClass { compact, medium, expanded, large }

extension WindowClassX on BuildContext {
  WindowClass get windowClass {
    final w = MediaQuery.sizeOf(this).width; // sizeOf: rebuilds only on size change
    if (w < 600) return WindowClass.compact;
    if (w < 840) return WindowClass.medium;
    if (w < 1200) return WindowClass.expanded;
    return WindowClass.large;
  }
}

class AppColumn<T> {
  const AppColumn({
    required this.label,
    required this.value,
    this.cell,
    this.numeric = false,
    this.sortable = true,
    this.size = ColumnSize.M,
    this.minWindow = WindowClass.compact,
  });

  final String label;
  final Comparable<dynamic> Function(T row) value; // sort key + default text
  final Widget Function(T row)? cell; // custom cell: chips, badges, buttons
  final bool numeric;
  final bool sortable;
  final ColumnSize size;
  final WindowClass minWindow; // hidden while the window is smaller than this
}

class AppRowAction<T> {
  const AppRowAction(this.label, this.icon, this.onTap);
  final String label;
  final IconData icon;
  final void Function(T row) onTap;
}

class AppDataTable<T> extends StatefulWidget {
  const AppDataTable({
    super.key,
    required this.columns,
    required this.rows,
    required this.searchText,
    this.title,
    this.toolbar = const [],
    this.actions = const [],
    this.onRowTap,
    this.cardBuilder,
    this.loading = false,
    this.emptyMessage = 'Nothing to show',
    this.compactBelow = 720,
  });

  final List<AppColumn<T>> columns;
  final List<T> rows;
  final String Function(T row) searchText; // what the search box matches against
  final String? title;
  final List<Widget> toolbar; // filter chips / date pickers / "Add" button
  final List<AppRowAction<T>> actions;
  final void Function(T row)? onRowTap;
  final Widget Function(BuildContext, T row)? cardBuilder;
  final bool loading;
  final String emptyMessage;
  final double compactBelow;

  @override
  State<AppDataTable<T>> createState() => _AppDataTableState<T>();
}

class _AppDataTableState<T> extends State<AppDataTable<T>> {
  final _search = TextEditingController();
  int? _sortCol;
  bool _asc = true;
  int _rowsPerPage = 10;
  late _Source<T> _source;

  @override
  void initState() {
    super.initState();
    _source = _Source<T>();
  }

  @override
  void dispose() {
    _search.dispose();
    _source.dispose();
    super.dispose();
  }

  List<AppColumn<T>> _visibleColumns(BuildContext context) {
    final cls = context.windowClass.index;
    return widget.columns.where((c) => cls >= c.minWindow.index).toList();
  }

  List<T> _processed(List<AppColumn<T>> cols) {
    final q = _search.text.trim().toLowerCase();
    var out = q.isEmpty ? [...widget.rows] : widget.rows.where((r) => widget.searchText(r).toLowerCase().contains(q)).toList();
    if (_sortCol != null && _sortCol! < cols.length) {
      final c = cols[_sortCol!];
      out.sort((a, b) => _asc ? c.value(a).compareTo(c.value(b)) : c.value(b).compareTo(c.value(a)));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final compact = MediaQuery.sizeOf(context).width < widget.compactBelow;
    final cols = _visibleColumns(context);
    final rows = _processed(cols);

    final header = Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (widget.title != null) Text(widget.title!, style: Theme.of(context).textTheme.titleLarge),
        SizedBox(
          width: compact ? double.infinity : 280,
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Search…',
              prefixIcon: const Icon(Icons.search, size: 20),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        ...widget.toolbar,
      ],
    );

    Widget body;
    if (widget.loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (rows.isEmpty) {
      body = Center(child: Text(widget.emptyMessage, style: TextStyle(color: scheme.onSurfaceVariant)));
    } else if (compact) {
      body = ListView.separated(
        padding: const EdgeInsets.only(top: 8),
        itemCount: rows.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (ctx, i) => widget.cardBuilder != null
            ? widget.cardBuilder!(ctx, rows[i])
            : _DefaultCard<T>(row: rows[i], cols: cols, onTap: widget.onRowTap),
      );
    } else {
      _source.update(rows, cols, widget.onRowTap, widget.actions, context);
      body = PaginatedDataTable2(
        source: _source,
        minWidth: 720,
        rowsPerPage: _rowsPerPage,
        availableRowsPerPage: const [10, 25, 50],
        onRowsPerPageChanged: (v) => setState(() => _rowsPerPage = v ?? 10),
        sortColumnIndex: _sortCol,
        sortAscending: _asc,
        headingRowHeight: 48,
        dataRowHeight: 56,
        horizontalMargin: 16,
        columnSpacing: 12,
        showCheckboxColumn: false,
        headingRowColor: WidgetStatePropertyAll(scheme.surfaceContainerHighest),
        columns: [
          for (var i = 0; i < cols.length; i++)
            DataColumn2(
              label: Text(cols[i].label, style: const TextStyle(fontWeight: FontWeight.w700)),
              size: cols[i].size,
              numeric: cols[i].numeric,
              onSort: cols[i].sortable ? (idx, asc) => setState(() { _sortCol = idx; _asc = asc; }) : null,
            ),
          if (widget.actions.isNotEmpty) const DataColumn2(label: SizedBox.shrink(), fixedWidth: 56),
        ],
      );
    }

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [header, const SizedBox(height: 12), Expanded(child: body)]),
      ),
    );
  }
}

class _Source<T> extends DataTableSource {
  List<T> rows = const [];
  List<AppColumn<T>> cols = const [];
  void Function(T)? onTap;
  List<AppRowAction<T>> actions = const [];
  BuildContext? ctx;

  void update(List<T> r, List<AppColumn<T>> c, void Function(T)? tap, List<AppRowAction<T>> a, BuildContext context) {
    rows = r; cols = c; onTap = tap; actions = a; ctx = context;
  }

  @override
  DataRow? getRow(int index) {
    if (index >= rows.length) return null;
    final r = rows[index];
    return DataRow2.byIndex(
      index: index,
      onTap: onTap == null ? null : () => onTap!(r),
      cells: [
        for (final c in cols) DataCell(c.cell?.call(r) ?? Text('${c.value(r)}', overflow: TextOverflow.ellipsis)),
        if (actions.isNotEmpty)
          DataCell(PopupMenuButton<AppRowAction<T>>(
            tooltip: 'Actions', // desktop users expect hover tooltips on icon buttons
            icon: const Icon(Icons.more_vert, size: 20),
            onSelected: (a) => a.onTap(r),
            itemBuilder: (_) => [for (final a in actions) PopupMenuItem(value: a, child: Row(children: [Icon(a.icon, size: 18), const SizedBox(width: 10), Text(a.label)]))],
          )),
      ],
    );
  }

  @override bool get isRowCountApproximate => false;
  @override int get rowCount => rows.length;
  @override int get selectedRowCount => 0;
}

class _DefaultCard<T> extends StatelessWidget {
  const _DefaultCard({required this.row, required this.cols, this.onTap});
  final T row;
  final List<AppColumn<T>> cols;
  final void Function(T)? onTap;

  @override
  Widget build(BuildContext context) {
    final first = cols.first;
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap == null ? null : () => onTap!(row),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            first.cell?.call(row) ?? Text('${first.value(row)}', style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            for (final c in cols.skip(1))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(children: [
                  SizedBox(width: 96, child: Text(c.label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12))),
                  Expanded(child: Align(alignment: Alignment.centerLeft, child: c.cell?.call(row) ?? Text('${c.value(row)}'))),
                ]),
              ),
          ]),
        ),
      ),
    );
  }
}
