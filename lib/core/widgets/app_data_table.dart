// App-level data table ("datacell" grid) used for every list/report screen.
//
//   * wide windows   -> sticky-header, sortable, paginated table with row actions
//   * compact (<720) -> the same rows as tappable cards (touch-friendly)
//   * columns can hide themselves below a window class (responsive columns)
//
// Callers only ever import this file, never data_table_2 directly, so the
// underlying table library stays swappable.
import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';
import 'window_class.dart';

export 'package:data_table_2/data_table_2.dart' show ColumnSize;

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
  final Widget Function(T row)? cell; // custom cell: chips, badges, images
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

/// Desktop-grade data table that degrades to a card list on phones.
///
/// Every list/report screen (Table Master, User Master, Item Master, Bills)
/// should render its rows through this widget instead of a bespoke
/// `ListView` of cards, so paging/sorting/search behave identically
/// everywhere and the app looks like one system rather than 20 one-offs.
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
    this.rowsPerPage = 10,
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
  final int rowsPerPage;

  @override
  State<AppDataTable<T>> createState() => _AppDataTableState<T>();
}

class _AppDataTableState<T> extends State<AppDataTable<T>> {
  final _search = TextEditingController();
  int? _sortCol;
  bool _asc = true;
  late int _rowsPerPage;
  late final _Source<T> _source;

  @override
  void initState() {
    super.initState();
    _rowsPerPage = widget.rowsPerPage;
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
    var out = q.isEmpty
        ? [...widget.rows]
        : widget.rows.where((r) => widget.searchText(r).toLowerCase().contains(q)).toList();
    if (_sortCol != null && _sortCol! < cols.length) {
      final c = cols[_sortCol!];
      out.sort((a, b) => _asc ? c.value(a).compareTo(c.value(b)) : c.value(b).compareTo(c.value(a)));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final headerBg = isDark ? AppColors.darkElevated : AppColors.lightElevated;
    final compact = MediaQuery.sizeOf(context).width < widget.compactBelow;
    final cols = _visibleColumns(context);
    final rows = _processed(cols);

    final header = Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (widget.title != null)
          Text(
            widget.title!,
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: isDark ? AppColors.textWhite : AppColors.textDark,
            ),
          ),
        SizedBox(
          width: compact ? double.infinity : 280,
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            style: GoogleFonts.inter(fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Search…',
              hintStyle: GoogleFonts.inter(fontSize: 13),
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              isDense: true,
              filled: true,
              fillColor: isDark ? AppColors.darkBg : AppColors.lightBg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: borderColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: borderColor),
              ),
            ),
          ),
        ),
        ...widget.toolbar,
      ],
    );

    Widget body;
    if (widget.loading) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (rows.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Center(
          child: Text(
            widget.emptyMessage,
            style: GoogleFonts.inter(
              color: isDark ? AppColors.textWhiteMuted : AppColors.textDarkMuted,
            ),
          ),
        ),
      );
    } else if (compact) {
      body = ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 8),
        itemCount: rows.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (ctx, i) => widget.cardBuilder != null
            ? widget.cardBuilder!(ctx, rows[i])
            : _DefaultCard<T>(row: rows[i], cols: cols, onTap: widget.onRowTap),
      );
    } else {
      _source.update(rows, cols, widget.onRowTap, widget.actions);
      body = SizedBox(
        height: (_rowsPerPage * 52.0) + 120,
        child: PaginatedDataTable2(
          source: _source,
          minWidth: 720,
          rowsPerPage: _rowsPerPage,
          availableRowsPerPage: const [10, 25, 50],
          onRowsPerPageChanged: (v) => setState(() => _rowsPerPage = v ?? 10),
          sortColumnIndex: _sortCol,
          sortAscending: _asc,
          headingRowHeight: 44,
          dataRowHeight: 52,
          horizontalMargin: 16,
          columnSpacing: 12,
          showCheckboxColumn: false,
          headingRowColor: WidgetStatePropertyAll(headerBg),
          headingTextStyle: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            fontSize: 12,
            color: isDark ? AppColors.textWhite : AppColors.textDark,
          ),
          dataTextStyle: GoogleFonts.inter(
            fontSize: 13,
            color: isDark ? AppColors.textWhite : AppColors.textDark,
          ),
          border: TableBorder(
            horizontalInside: BorderSide(color: borderColor, width: 0.6),
          ),
          columns: [
            for (var i = 0; i < cols.length; i++)
              DataColumn2(
                label: Text(cols[i].label),
                size: cols[i].size,
                numeric: cols[i].numeric,
                onSort: cols[i].sortable
                    ? (idx, asc) => setState(() {
                        _sortCol = idx;
                        _asc = asc;
                      })
                    : null,
              ),
            if (widget.actions.isNotEmpty) const DataColumn2(label: SizedBox.shrink(), fixedWidth: 56),
          ],
        ),
      );
    }

    return Card(
      elevation: 0,
      color: isDark ? AppColors.darkCard : AppColors.lightSurface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: borderColor),
      ),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [header, const SizedBox(height: 12), body],
        ),
      ),
    );
  }
}

class _Source<T> extends DataTableSource {
  List<T> rows = const [];
  List<AppColumn<T>> cols = const [];
  void Function(T)? onTap;
  List<AppRowAction<T>> actions = const [];

  void update(List<T> r, List<AppColumn<T>> c, void Function(T)? tap, List<AppRowAction<T>> a) {
    rows = r;
    cols = c;
    onTap = tap;
    actions = a;
    notifyListeners();
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
          DataCell(
            PopupMenuButton<AppRowAction<T>>(
              tooltip: 'Actions',
              icon: const Icon(Icons.more_vert_rounded, size: 20),
              onSelected: (a) => a.onTap(r),
              itemBuilder: (_) => [
                for (final a in actions)
                  PopupMenuItem(
                    value: a,
                    child: Row(
                      children: [
                        Icon(a.icon, size: 18),
                        const SizedBox(width: 10),
                        Text(a.label, style: GoogleFonts.inter(fontSize: 13)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  @override
  bool get isRowCountApproximate => false;
  @override
  int get rowCount => rows.length;
  @override
  int get selectedRowCount => 0;
}

class _DefaultCard<T> extends StatelessWidget {
  const _DefaultCard({required this.row, required this.cols, this.onTap});
  final T row;
  final List<AppColumn<T>> cols;
  final void Function(T)? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final first = cols.first;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: isDark ? AppColors.darkCard : AppColors.lightSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: borderColor),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap == null ? null : () => onTap!(row),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DefaultTextStyle.merge(
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: isDark ? AppColors.textWhite : AppColors.textDark,
                ),
                child: first.cell?.call(row) ?? Text('${first.value(row)}'),
              ),
              const SizedBox(height: 6),
              for (final c in cols.skip(1))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 96,
                        child: Text(
                          c.label,
                          style: GoogleFonts.inter(
                            color: isDark ? AppColors.textWhiteMuted : AppColors.textDarkMuted,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: DefaultTextStyle.merge(
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: isDark ? AppColors.textWhite : AppColors.textDark,
                            ),
                            child: c.cell?.call(row) ?? Text('${c.value(row)}'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
