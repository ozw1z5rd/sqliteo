import SwiftUI

struct DataTableView: View {
    @Environment(DatabaseManager.self) private var dbManager

    var body: some View {
        VStack(spacing: 0) {
            if dbManager.selectedTableName != nil {
                FilterView()
                    .padding(.bottom, 8)
                    .background(Color(NSColor.windowBackgroundColor))

                Divider()
            }

            if dbManager.columns.isEmpty {
                VStack {
                    Spacer()
                    Text("No data to display")
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { geometry in
                    ZStack(alignment: .bottom) {
                        ScrollView([.horizontal, .vertical]) {
                            LazyVStack(
                                alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]
                            ) {
                                Section(header: HeaderView(columns: dbManager.columns)) {
                                    ForEach(dbManager.rows) { row in
                                        RowView(
                                            row: row, columns: dbManager.columns, isSelected: false)
                                    }
                                }
                            }
                            // Add extra padding at the bottom so content isn't covered by the edit bar
                            .padding(.bottom, !dbManager.activeEdits.isEmpty ? 60 : 0)
                            .frame(
                                minWidth: max(
                                    geometry.size.width, CGFloat(dbManager.columns.count) * 150),
                                minHeight: geometry.size.height,
                                alignment: .topLeading
                            )
                        }
                        .padding(.horizontal)

                        if !dbManager.activeEdits.isEmpty {
                            EditControlBar()
                                .transition(.move(edge: .bottom))
                        }
                    }
                }
            }

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct EditControlBar: View {
    @Environment(DatabaseManager.self) private var dbManager

    var body: some View {
        HStack {
            Text("Editing \(dbManager.activeEdits.count) cell(s)...")
                .font(.headline)
                .foregroundColor(.secondary)

            Spacer()

            Button {
                dbManager.cancelEdits()
            } label: {
                Text("Cancel")
            }
            .keyboardShortcut(.escape, modifiers: [])

            Button {
                dbManager.applyEdits()
            } label: {
                Text("Apply")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: [])
        }
        .padding()
        .background(.ultraThinMaterial)
        .overlay(Divider(), alignment: .top)
    }
}

struct HeaderView: View {
    let columns: [String]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(columns, id: \.self) { column in
                Text(column)
                    .font(.headline)
                    .padding(8)
                    .frame(width: 150, alignment: .leading)
                    .background(Color(NSColor.windowBackgroundColor))
                    .border(Color.secondary.opacity(0.2))
            }
            Spacer(minLength: 0)
        }
    }
}

struct RowView: View {
    @Environment(DatabaseManager.self) private var dbManager
    let row: DBRow
    let columns: [String]
    let isSelected: Bool

    var body: some View {
        let rowData = RowData(
            row: row,
            columns: columns,
            isSelected: isSelected,
            activeEdits: dbManager.activeEdits[row.id] ?? [:],
            pendingChanges: dbManager.pendingChanges[row.id] ?? [:]
        )
        RowContentView(
            data: rowData,
            onStartEditing: { col, val in
                dbManager.startEditing(rowID: row.id, column: col, currentValue: val)
            },
            onUpdateEdit: { col, val in
                dbManager.updateActiveEdit(rowID: row.id, column: col, value: val)
            }
        )
    }
}

struct RowData: Equatable {
    let row: DBRow
    let columns: [String]
    let isSelected: Bool
    let activeEdits: [String: String]
    let pendingChanges: [String: String]
}

struct RowContentView: View, Equatable {
    let data: RowData
    let onStartEditing: (String, String) -> Void
    let onUpdateEdit: (String, String) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(data.columns, id: \.self) { column in
                let cellData = CellData(
                    rowID: data.row.id,
                    column: column,
                    initialValue: data.row.data[column] ?? "",
                    activeEdit: data.activeEdits[column],
                    pendingChange: data.pendingChanges[column]
                )
                CellView(
                    data: cellData,
                    onStartEditing: { val in onStartEditing(column, val) },
                    onUpdateEdit: { val in onUpdateEdit(column, val) }
                )
            }
            Spacer(minLength: 0)
        }
        .frame(height: 33)
    }

    nonisolated static func == (lhs: RowContentView, rhs: RowContentView) -> Bool {
        lhs.data == rhs.data
    }
}

struct CellData: Equatable {
    let rowID: TableRowID
    let column: String
    let initialValue: String
    let activeEdit: String?
    let pendingChange: String?
}

struct CellView: View {
    let data: CellData
    let onStartEditing: (String) -> Void
    let onUpdateEdit: (String) -> Void

    var body: some View {
        CellContentView(
            data: data,
            onStartEditing: onStartEditing,
            onUpdateEdit: onUpdateEdit
        )
    }
}

struct CellContentView: View, Equatable {
    let data: CellData
    let onStartEditing: (String) -> Void
    let onUpdateEdit: (String) -> Void

    var body: some View {
        ZStack(alignment: .leading) {
            if let activeEdit = data.activeEdit {
                TextField(
                    "",
                    text: Binding(
                        get: { activeEdit },
                        set: { onUpdateEdit($0) }
                    )
                )
                .textFieldStyle(.plain)
                .padding(8)
                .frame(width: 150, alignment: .leading)
                .background(Color.blue.opacity(0.1))
            } else {
                Text(displayValue)
                    .lineLimit(1)
                    .padding(8)
                    .frame(width: 150, alignment: .leading)
                    .background(data.pendingChange != nil ? Color.yellow.opacity(0.1) : Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onStartEditing(displayValue)
                    }
            }
        }
        .border(Color.secondary.opacity(0.1))
    }

    var displayValue: String {
        data.pendingChange ?? data.initialValue
    }

    nonisolated static func == (lhs: CellContentView, rhs: CellContentView) -> Bool {
        lhs.data == rhs.data
    }
}
