import SwiftUI

private let availableLanguages: [(id: String, label: String)] = [
    ("system", "lang_system"),
    ("en", "English"),
    ("zh-Hans", "简体中文"),
    ("zh-Hant", "繁體中文"),
]

struct LanguagePickerView: View {
    @Binding var selected: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(availableLanguages, id: \.id) { lang in
                    Button {
                        selected = lang.id
                        dismiss()
                    } label: {
                        HStack {
                            Text(lang.id == "system"
                                 ? String(localized: "lang_system")
                                 : lang.label)
                                .foregroundColor(.primary)
                            Spacer()
                            if selected == lang.id {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "lang_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .fontWeight(.semibold)
                    }
                }
            }
        }
        .presentationDetents([.large])
    }
}
