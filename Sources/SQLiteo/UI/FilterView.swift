import SwiftUI

struct FilterView: View {
    @EnvironmentObject private var dbManager: DatabaseManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(dbManager.filters.indices, id: \.self) { index in
                HStack {
                    if !dbManager.columns.isEmpty {
                        Picker("Column", selection: Binding(
                            get: { dbManager.filters[index].column },
                            set: { dbManager.filters[index].column = $0 }
                        )) {
                            ForEach(dbManager.columns, id: \.self) { column in
                                Text(column).tag(column)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 150)
                    }

                    Picker("Operator", selection: Binding(
                        get: { dbManager.filters[index].operatorType },
                        set: { dbManager.filters[index].operatorType = $0 }
                    )) {
                        ForEach(DatabaseManager.FilterOperator.allCases) { op in
                            Text(op.rawValue).tag(op)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 120)

                    TextField("Value", text: Binding(
                        get: { dbManager.filters[index].value },
                        set: { dbManager.filters[index].value = $0 }
                    ))
                        .textFieldStyle(.roundedBorder)

                    Button {
                        let id = dbManager.filters[index].id
                        if let idx = dbManager.filters.firstIndex(where: { $0.id == id }) {
                            dbManager.filters.remove(at: idx)
                        }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                Button {
                    let firstColumn = dbManager.columns.first ?? ""
                    let newFilter = DatabaseManager.FilterCriteria(
                        column: firstColumn,
                        operatorType: .contains,
                        value: ""
                    )
                    dbManager.filters.append(newFilter)
                } label: {
                    Label("Add Filter", systemImage: "plus.circle")
                }
                .buttonStyle(.plain)
                .disabled(dbManager.columns.isEmpty)

                Spacer()

                if dbManager.isLoading {
                    Button("Cancel") {
                        dbManager.cancelQuery()
                    }
                    .buttonStyle(.bordered)
                }

                Button("Apply") {
                    Task {
                        await dbManager.applyFilter()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(dbManager.filters.isEmpty)

                Button("Clear") {
                    Task {
                        await dbManager.clearFilter()
                    }
                }
                .disabled(dbManager.filters.isEmpty)
            }
        }
        .padding(8)
    }
}
