import SwiftUI

struct FilterSheetView: View {
    @Binding var sortField: String
    @Binding var sortOrder: String
    @Binding var dateEnabled: Bool
    @Binding var dateFrom: Date
    @Binding var dateTo: Date
    @Binding var newOnly: Bool
    @Binding var untaggedOnly: Bool
    @Binding var favoriteOnly: Bool
    let onReset: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var showResetConfirm = false

    private let sortOptions: [(id: String, label: LocalizedStringKey)] = [
        ("relevance", "sort_relevance"),
        ("lastreadtime", "sort_lastread"),
        ("created_at", "sort_created"),
        ("release_at", "sort_release"),
        ("updated_at", "sort_updated"),
        ("title", "sort_title"),
        ("pagecount", "sort_pages"),
        ("", "sort_default"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "filter_sort")) {
                    Picker(String(localized: "filter_sort_field"), selection: $sortField) {
                        ForEach(sortOptions, id: \.id) { opt in
                            Text(opt.label).tag(opt.id)
                        }
                    }

                    HStack {
                        Text(String(localized: "filter_sort_order"))
                        Spacer()
                        NativeSegmentedControl(
                            selection: $sortOrder,
                            items: [
                                (nil, String(localized: "sort_desc"), "desc"),
                                (nil, String(localized: "sort_asc"), "asc"),
                            ]
                        )
                        .frame(width: 140)
                    }
                }

                Section(String(localized: "filter_date")) {
                    Toggle(String(localized: "filter_date_enable"), isOn: $dateEnabled)

                    DatePicker(
                        String(localized: "filter_date_from"),
                        selection: $dateFrom,
                        displayedComponents: .date
                    )
                    .disabled(!dateEnabled)
                    .foregroundColor(dateEnabled ? .primary : .secondary)

                    DatePicker(
                        String(localized: "filter_date_to"),
                        selection: $dateTo,
                        displayedComponents: .date
                    )
                    .disabled(!dateEnabled)
                    .foregroundColor(dateEnabled ? .primary : .secondary)
                }

                Section {
                    Toggle(String(localized: "filter_new_only"), isOn: $newOnly)
                    Toggle(String(localized: "filter_untagged"), isOn: $untaggedOnly)
                    Toggle(String(localized: "filter_favorites"), isOn: $favoriteOnly)
                }

                Section {
                    Button(String(localized: "filter_reset"), role: .destructive) {
                        showResetConfirm = true
                    }
                }
            }
            .navigationTitle(String(localized: "filter_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").fontWeight(.semibold)
                    }
                }
            }
        }
        .presentationDetents([.large])
        .alert(String(localized: "filter_reset_confirm"), isPresented: $showResetConfirm) {
            Button(String(localized: "cancel"), role: .cancel) {}
            Button(String(localized: "confirm_reset"), role: .destructive) {
                onReset()
                dismiss()
            }
        }
    }
}
