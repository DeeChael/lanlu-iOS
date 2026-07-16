import SwiftUI

enum ServerSetting: String, CaseIterable, Identifiable {
    case accountSecurity
    case category
    case tags
    case smartFilters
    case userManagement
    case systemSettings
    case backgroundTasks
    case scheduledTasks
    case pluginManagement
    case statistics

    var id: Self { self }

    var title: String {
        switch self {
        case .accountSecurity: String(localized: "ss_account_security")
        case .category: String(localized: "ss_category")
        case .tags: String(localized: "ss_tags")
        case .smartFilters: String(localized: "ss_smart_filters")
        case .userManagement: String(localized: "ss_user_management")
        case .systemSettings: String(localized: "ss_system_settings")
        case .backgroundTasks: String(localized: "ss_background_tasks")
        case .scheduledTasks: String(localized: "ss_scheduled_tasks")
        case .pluginManagement: String(localized: "ss_plugin_management")
        case .statistics: String(localized: "ss_statistics")
        }
    }

    var systemImage: String {
        switch self {
        case .accountSecurity: "shield"
        case .category: "folder"
        case .tags: "tag"
        case .smartFilters: "line.3.horizontal.decrease"
        case .userManagement: "person.2"
        case .systemSettings: "server.rack"
        case .backgroundTasks: "calendar.badge.clock"
        case .scheduledTasks: "clock"
        case .pluginManagement: "puzzlepiece"
        case .statistics: "chart.bar"
        }
    }
}

struct ServerSettingDetailView: View {
    let server: Server
    let setting: ServerSetting

    var body: some View {
        Group {
            if setting == .accountSecurity {
                AccountSecurityView(server: server)
            } else if setting == .category {
                CategoryManagementView(server: server)
            } else if setting == .tags {
                TagManagementView(server: server)
            } else if setting == .smartFilters {
                SmartFilterManagementView(server: server)
            } else {
                List {
                    Section {
                        ContentUnavailableView {
                            Label(setting.title, systemImage: setting.systemImage)
                        } description: {
                            Text("server_setting_detail_placeholder")
                        }
                    }
                }
            }
        }
        .navigationTitle(setting.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }
}
