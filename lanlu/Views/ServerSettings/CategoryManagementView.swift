import SwiftUI

struct CategoryManagementView: View {
    let server: Server

    @State private var categories: [APIClient.CategoryItem] = []
    @State private var enabledStates: [Int: Bool] = [:]
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showCreateCategory = false

    var body: some View {
        List {
            if isLoading && categories.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }

            ForEach(categories, id: \.id) { category in
                CategoryManagementRow(
                    server: server,
                    category: category,
                    enabled: enabledBinding(for: category)
                )
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 16))
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {} label: {
                        swipeActionIcon(
                            systemName: "trash",
                            color: .red,
                            accessibilityLabel: String(localized: "delete")
                        )
                    }

                    Button {} label: {
                        swipeActionIcon(
                            systemName: "pencil",
                            color: .blue,
                            accessibilityLabel: String(localized: "edit")
                        )
                    }
                    .tint(.blue)

                    Button {} label: {
                        swipeActionIcon(
                            systemName: "play",
                            color: .green,
                            accessibilityLabel: String(localized: "scan")
                        )
                    }
                    .tint(.green)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showCreateCategory = true
                } label: {
                    Image(systemName: "plus")
                        .fontWeight(.semibold)
                }
            }
        }
        .sheet(isPresented: $showCreateCategory) {
            CreateCategoryView()
                .presentationDetents([.large])
        }
        .task {
            await loadCategories()
        }
    }

    private func enabledBinding(for category: APIClient.CategoryItem) -> Binding<Bool> {
        Binding(
            get: { enabledStates[category.id] ?? category.enabled ?? false },
            set: { enabledStates[category.id] = $0 }
        )
    }

    private func swipeActionIcon(
        systemName: String,
        color: Color,
        accessibilityLabel: String
    ) -> some View {
        Image(systemName: systemName)
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 40, height: 40)
            .background(color, in: Circle())
            .accessibilityLabel(accessibilityLabel)
    }

    private func loadCategories() async {
        isLoading = true
        errorMessage = nil
        LogManager.shared.log("[Categories] Load started")
        do {
            let loadedCategories = try await server.apiClient.fetchCategories()
            categories = loadedCategories
            enabledStates = Dictionary(
                uniqueKeysWithValues: loadedCategories.map { ($0.id, $0.enabled ?? false) }
            )
            LogManager.shared.log("[Categories] Load completed count=\(loadedCategories.count)")
        } catch {
            errorMessage = error.localizedDescription
            LogManager.shared.log("[Categories] Load failed: \(error.localizedDescription)")
        }
        isLoading = false
    }
}

private struct CategoryManagementRow: View {
    let server: Server
    let category: APIClient.CategoryItem
    @Binding var enabled: Bool

    @State private var coverImage: UIImage?

    var body: some View {
        HStack(spacing: 12) {
            if coverImage == nil {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(category.name)
                            .fontWeight(.medium)
                        archiveCountBadge
                    }

                    if let description = category.description, !description.isEmpty {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 16)
            }

            Spacer(minLength: 8)

            if coverImage != nil {
                archiveCountBadge
            }

            Toggle("", isOn: $enabled)
                .labelsHidden()
        }
        .frame(minHeight: 72)
        .background(alignment: .leading) {
            if let coverImage {
                GeometryReader { proxy in
                    Image(uiImage: coverImage)
                        .resizable()
                        .scaledToFill()
                        .frame(
                            width: proxy.size.width * 2 / 3,
                            height: proxy.size.height,
                            alignment: .leading
                        )
                        .clipped()
                        .mask {
                            LinearGradient(
                                stops: [
                                    .init(color: .black, location: 0),
                                    .init(color: .black, location: 0.5),
                                    .init(color: .clear, location: 1)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        }
                }
            }
        }
        .task(id: category.coverAssetId) {
            await loadCover()
        }
    }

    private var archiveCountBadge: some View {
        Text(String(format: String(localized: "category_archive_count"), category.archiveCount ?? 0))
            .font(.caption2)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .glassEffect(.regular, in: Capsule())
    }

    private func loadCover() async {
        guard let assetId = category.coverAssetId else {
            coverImage = nil
            return
        }
        guard let data = try? await server.apiClient.fetchAsset(assetId: assetId),
              let image = UIImage(data: data) else {
            coverImage = nil
            LogManager.shared.log("[Categories] Cover unavailable assetId=\(assetId)")
            return
        }
        coverImage = image
    }
}

private struct CreateCategoryView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Color.clear
                .navigationTitle(String(localized: "create_category"))
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
}
