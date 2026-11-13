import SwiftData
import SwiftUI

/// A sheet for saying what a line was: its group, its sub-category, and for
/// expenses whether it is fixed, variable or one-time. The answer is
/// remembered for future lines from the same place.
struct CategoryPicker: View {
    let entry: LedgerEntry
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CustomSub.createdAt) private var customSubs: [CustomSub]
    @State private var search = ""
    @State private var addingTo: SpendCategory?
    @State private var newName = ""

    private var groups: [SpendCategory] {
        if entry.amount > 0 {
            return SpendCategory.all.filter { $0.id == SpendCategory.incomeID || $0.id == SpendCategory.transferID }
        }
        return SpendCategory.all.filter { $0.id != SpendCategory.incomeID }
    }

    private func subs(in group: SpendCategory) -> [SubCategory] {
        let own = customSubs
            .filter { $0.groupID == group.id }
            .map { SubCategory(id: $0.id, groupID: group.id, title: $0.title, nature: .variable) }
        let all = SubCategory.inGroup(group.id) + own
        let text = search.trimmingCharacters(in: .whitespaces)
        if text.isEmpty || group.title.contains(text) { return all }
        return all.filter { $0.title.contains(text) }
    }

    private func isShown(_ group: SpendCategory) -> Bool {
        let text = search.trimmingCharacters(in: .whitespaces)
        return text.isEmpty || group.title.contains(text) || !subs(in: group).isEmpty
    }

    private var nature: Binding<Nature> {
        Binding(
            get: { entry.nature },
            set: { value in
                entry.natureOverride = value.rawValue
                try? context.save()
            })
    }

    var body: some View {
        NavigationStack {
            List {
                if entry.amount < 0 {
                    Section {
                        Picker("סוג ההוצאה", selection: nature) {
                            ForEach(Nature.allCases) { item in
                                Text(item.title).tag(item)
                            }
                        }
                        .pickerStyle(.segmented)
                    } header: {
                        Text("\(entry.title) · \(Money.text(entry.amount, fractionDigits: 2))")
                    } footer: {
                        Text("קבועה חוזרת כל חודש. חד פעמית לא נכנסת לממוצע החודשי.")
                    }
                }

                ForEach(groups.filter(isShown)) { group in
                    Section {
                        row(group.title + " · כללי",
                            isSelected: entry.categoryID == group.id && entry.subID == nil) {
                            choose(group, nil)
                        }
                        ForEach(subs(in: group)) { sub in
                            row(sub.title, isSelected: entry.subID == sub.id) {
                                choose(group, sub)
                            }
                        }
                        Button {
                            newName = ""
                            addingTo = group
                        } label: {
                            Label("תת קטגוריה חדשה", systemImage: "plus")
                                .font(.system(size: 15, weight: .semibold))
                        }
                    } header: {
                        Label(group.title, systemImage: group.symbol)
                    }
                }
            }
            .searchable(text: $search, prompt: "חיפוש קטגוריה")
            .navigationTitle("מה זה היה?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("סגירה") { dismiss() }
                }
            }
            .alert("תת קטגוריה חדשה", isPresented: isAdding) {
                TextField("שם", text: $newName)
                Button("הוספה") { addSub() }
                Button("ביטול", role: .cancel) {}
            } message: {
                Text(addingTo?.title ?? "")
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .presentationDetents([.large])
    }

    private var isAdding: Binding<Bool> {
        Binding(get: { addingTo != nil }, set: { if !$0 { addingTo = nil } })
    }

    private func row(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 17, weight: isSelected ? .bold : .regular))
                    .foregroundStyle(Color.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .bold))
                }
            }
            .contentShape(Rectangle())
        }
    }

    private func choose(_ group: SpendCategory, _ sub: SubCategory?) {
        Ledger.answer(entry, with: group, sub: sub, in: context)
        dismiss()
    }

    private func addSub() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard let group = addingTo, !name.isEmpty else { return }
        let custom = CustomSub(groupID: group.id, title: name)
        context.insert(custom)
        try? context.save()
        addingTo = nil
        choose(group, SubCategory(id: custom.id, groupID: group.id, title: name, nature: .variable))
    }
}
