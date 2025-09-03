import SwiftUI

struct ContentView: View {
    @StateObject private var vm = HomeViewModel()
    @State private var editing: Transaction?

    var body: some View {
        NavigationStack {
            List {
                if vm.transactions.isEmpty {
                    Text("目前沒有紀錄")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(vm.transactions, id: \.id) { t in
                        HStack(spacing: 12) {
                            Image(systemName: t.category.sfSymbol)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(t.description)
                                    .font(.headline)
                                Text(t.date, style: .date)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text("NT$ \(t.amount, specifier: "%.2f")")
                                .font(.headline)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { editing = t }
                        .swipeActions {
                            Button(role: .destructive) {
                                vm.delete(id: t.id)
                            } label: {
                                Label("刪除", systemImage: "trash")
                            }
                        }
                    }
                    .onDelete(perform: vm.deleteAtOffsets)
                }
            }
            .navigationTitle("花費")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        // 你可以換成彈出新增畫面；這裡先放一筆範例資料方便測
                        vm.add(.sample)
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(item: $editing) { t in
            EditTransactionView(transaction: t) { updated in
                vm.update(updated)
            }
        }
    }
}

