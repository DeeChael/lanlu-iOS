import SwiftUI

struct ClientSettingsSheetView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage("theme_mode") private var themeMode = "system"
    @AppStorage("language") private var language = "system"

    @State private var showLanguagePicker = false
    @State private var showReaderSettings = false
    @State private var showDiagnostics = false
    @State private var showClearCacheAlert = false
    @State private var cacheInfo = ""

    private var languageLabel: String {
        switch language {
        case "en": "English"
        case "zh-Hans": "简体中文"
        case "zh-Hant": "繁體中文"
        default: String(localized: "lang_system")
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Label(String(localized: "setting_theme"), systemImage: "paintpalette.fill")
                        Spacer()
                        NativeSegmentedControl(
                            selection: $themeMode,
                            items: [
                                ("circle.righthalf.fill", nil, "system"),
                                ("sun.max.fill", nil, "light"),
                                ("moon.fill", nil, "dark"),
                            ]
                        )
                        .frame(width: 140)
                    }

                    Button {
                        showLanguagePicker = true
                    } label: {
                        HStack {
                            Label(String(localized: "setting_language"), systemImage: "globe.fill")
                            Spacer()
                            Text(languageLabel)
                                .foregroundColor(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .sheet(isPresented: $showLanguagePicker) {
                        LanguagePickerView(selected: $language)
                    }

                    Button {
                        showReaderSettings = true
                    } label: {
                        HStack {
                            Label(
                                String(localized: "reader_settings"),
                                systemImage: "book.pages.fill"
                            )
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .sheet(isPresented: $showReaderSettings) {
                        StandaloneReaderSettingsView()
                            .presentationDetents([.large])
                    }

                    Button {
                        showDiagnostics = true
                    } label: {
                        HStack {
                            Label(String(localized: "setting_diagnostics"), systemImage: "ant.fill")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .sheet(isPresented: $showDiagnostics) {
                        DiagnosticsView()
                    }

                    Button(role: .destructive) {
                        cacheInfo = String(
                            format: String(localized: "clear_cache_detail"),
                            CacheManager.shared.metadataDiskCount,
                            CacheManager.shared.imageDiskCount
                        )
                        showClearCacheAlert = true
                    } label: {
                        HStack {
                            Label(String(localized: "setting_clear_cache"), systemImage: "trash.fill")
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .tint(.red)
                    .alert(String(localized: "clear_cache_title"), isPresented: $showClearCacheAlert) {
                        Button(String(localized: "cancel"), role: .cancel) {}
                        Button(String(localized: "confirm"), role: .destructive) { clearCache() }
                    } message: {
                        Text(cacheInfo)
                    }
                }
            }
            .navigationTitle(String(localized: "client_settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .fontWeight(.semibold)
                    }
                }
            }
        }
    }

    private func clearCache() {
        URLCache.shared.removeAllCachedResponses()
        CacheManager.shared.clearAll()
        LogManager.shared.log("Cache cleared (URLCache + ArchiveCache)")
    }
}
