import PhotosUI
import SwiftUI

struct ComposerView: View {
    @StateObject private var model = ComposerModel()
    @State private var selectedItem: PhotosPickerItem?
    @State private var isAnimating = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                preview

                PhotosPicker(selection: $selectedItem, matching: .images) {
                    Label("选择照片", systemImage: "photo")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .onChange(of: selectedItem) { _, item in
                    guard let item else { return }
                    Task { await model.load(item) }
                }

                Button {
                    Task { await model.generateAndSave() }
                } label: {
                    HStack {
                        if model.isWorking {
                            ProgressView()
                        }
                        Text(model.isWorking ? model.status : "生成并保存 Live Photo")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.image == nil || model.isWorking)

                if !model.status.isEmpty && !model.isWorking {
                    Text(model.status)
                        .font(.footnote)
                        .foregroundStyle(model.didSucceed ? .green : .secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding()
            .navigationTitle("Live Photo")
        }
    }

    @ViewBuilder
    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(.secondary.opacity(0.12))

            if let image = model.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(isAnimating ? 1.075 : 1)
                    .clipped()
                    .onAppear { startPreview() }
                    .onChange(of: model.image) { _, _ in startPreview() }
            } else {
                ContentUnavailableView(
                    "选择一张静态照片",
                    systemImage: "livephoto",
                    description: Text("Phase 0 先验证稳定推近与 Live Photo 保存闭环")
                )
            }
        }
        .aspectRatio(9 / 16, contentMode: .fit)
        .frame(maxHeight: 560)
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    private func startPreview() {
        isAnimating = false
        withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: false)) {
            isAnimating = true
        }
    }
}
