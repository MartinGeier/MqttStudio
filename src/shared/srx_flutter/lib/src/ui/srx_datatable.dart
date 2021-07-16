import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

typedef List<Widget> GenerateRowCellsFunction(int index);
typedef void SortByColumnFucntion(int columnIndex, bool sortAscending);
typedef void ActionPressedFunction(int rowIndex, int actionIndex);
typedef void SelectionChangedFunction(int rowIndex);

class SrxDataTable extends StatefulWidget {
  final List<SrxDataColumn> columns;
  final int rowCount;
  final GenerateRowCellsFunction onRowCellChilds;
  final SortByColumnFucntion? onSortByColumn;
  final bool showRecordCount;
  final ActionPressedFunction? onActionPressed;
  final double? minWidth;
  final List<IconData>? actions;
  final List<int>? selectedRows;
  final SelectionChangedFunction? onSelectionChanged;
  final bool showCheckBoxColumn;
  final Widget noDataWidget;

  SrxDataTable(
      {required this.columns,
      required this.rowCount,
      required this.onRowCellChilds,
      this.onSortByColumn,
      this.showRecordCount = true,
      this.minWidth,
      this.actions,
      this.onActionPressed,
      this.selectedRows,
      this.onSelectionChanged,
      this.showCheckBoxColumn = false,
      required this.noDataWidget})
      : super();

  @override
  _SrxDataTableState createState() => _SrxDataTableState();
}

class _SrxDataTableState extends State<SrxDataTable> {
  int? _sortColumnIndex;
  bool _sortAscending = true;

  @override
  Widget build(BuildContext context) {
    var columns = List.generate(
        widget.columns.length,
        (index) => DataColumn2(
            onSort: widget.onSortByColumn != null ? (columnIndex, sortAscending) => _onSort(columnIndex, sortAscending) : null,
            label: widget.columns[index].label,
            size: widget.columns[index].columnSize,
            numeric: widget.columns[index].numeric));

    if (widget.actions != null) {
      var iconColumn = DataColumn2(label: Container(), numeric: true, size: ColumnSize.S);
      columns.add(iconColumn);
    }

    var rows = List<DataRow2>.generate(widget.rowCount, (index) => _generateRow(index));

    return Column(
      children: [
        Expanded(
          child: DataTable2(
              empty: widget.noDataWidget,
              sortAscending: _sortAscending,
              sortColumnIndex: _sortColumnIndex,
              showCheckboxColumn: widget.showCheckBoxColumn,
              columnSpacing: 8,
              minWidth: widget.minWidth,
              columns: columns,
              headingTextStyle: Theme.of(context).textTheme.subtitle2!.copyWith(fontWeight: FontWeight.bold),
              rows: rows),
        ),
        Visibility(
          visible: widget.showRecordCount,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  'srx.recordcount.label'.tr() + ' ${widget.rowCount.toString()}',
                ),
              ),
            ],
          ),
        )
      ],
    );
  }

  DataRow2 _generateRow(int rowIndex) {
    var cellChilds = widget.onRowCellChilds(rowIndex);
    var cells = List<DataCell>.generate(cellChilds.length, (index) => DataCell(cellChilds[index]));

    if (widget.actions != null) {
      var iconCell = DataCell(widget.selectedRows != null && widget.selectedRows!.contains(rowIndex)
          ? Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: List<Widget>.generate(widget.actions!.length, (actionIndex) => _buildAction(rowIndex, actionIndex)),
            )
          : Container());

      cells.add(iconCell);
    }

    return DataRow2(
        onSelectChanged: (selected) => _onSelectChanged(rowIndex, selected),
        cells: cells,
        selected: widget.selectedRows != null ? widget.selectedRows!.contains(rowIndex) : false);
  }

  _onSelectChanged(int rowIndex, bool? selected) {
    if (selected != null && widget.onSelectionChanged != null) {
      widget.onSelectionChanged!(rowIndex);
    }
  }

  _onSort(int columnIndex, bool sortAscending) {
    if (_sortColumnIndex == null) {
      _sortColumnIndex = columnIndex;
      _sortAscending = true;
    } else if (_sortColumnIndex == columnIndex) {
      _sortAscending = sortAscending;
    } else {
      _sortColumnIndex = columnIndex;
      _sortAscending = true;
    }
    if (widget.onSortByColumn != null) {
      widget.onSortByColumn!(columnIndex, _sortAscending);
    }
  }

  Widget _buildAction(int rowIndex, int actionIndex) {
    return Visibility(
        visible: widget.selectedRows != null && widget.selectedRows!.length == 1 && widget.selectedRows!.contains(rowIndex),
        child: IconButton(
          icon: Icon(widget.actions![actionIndex]),
          onPressed: widget.onActionPressed != null ? () => widget.onActionPressed!(rowIndex, actionIndex) : null,
        ));
  }
}

class SrxDataColumn {
  final Widget label;
  final ColumnSize columnSize;
  final bool numeric;

  SrxDataColumn({required this.label, required this.columnSize, this.numeric = false});
}
